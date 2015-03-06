#!/usr/bin/env ruby
# encoding: utf-8

require "cuba"
require "cuba/contrib"
require "mote"
require "ohm"
require "ohm/contrib"
require "u2f"
require "shield"
require "rack/static"

require "./models"

Ohm.redis = Redic.new(ENV['REDISTOGO_URL'] || ENV['REDIS_URL'] || "redis://localhost:6379")

module Helpers
  def u2f
    @u2f ||= U2F::U2F.new(req.base_url)
  end

  # Halt with the given error
  def error code
    halt [code, {}, []]
  end

  # Get the current user (if any)
  def current_user
    authenticated(User)
  end

  # Ensure a user is authenticated
  # or force a redirect to login
  def authenticated!
    error(401) unless current_user
  end

  # Set HTTP Redirection and halt immediately
  def redirect path
    res.redirect path
    halt res.finish
  end
end


# All Routes:
#
# GET  /                  - Homepage with login form
# GET  /register          - Register form for new account
# POST /register          - Register new form and redirect to login
# GET  /private           - Private section
# GET  /private/keys      - List registered auth keys
# GET  /private/keys/add  - Form to add new auth key
# POST /private/keys/add  - Register new auth key
# GET  /logout            - Logout current user
# GET  /login             - Login form
# POST /login             - Authenticate current user
# GET  /login/key         - Form for key authentication
# POST /login/key         - Verify key authentication and redirect

Cuba.plugin Cuba::Mote
Cuba.plugin Cuba::TextHelpers

# Use Cookies, the secret should be random
# Generate a new one with:
#     openssl rand -base64 32
Cuba.use Rack::Session::Cookie, :secret => "g+8oAKCmyJq46kjPmZ18nxCdcqeaujSIWu5p/Jl+h+0="

# Authentication is handled by Shield
Cuba.plugin Shield::Helpers
Cuba.use Shield::Middleware, "/login"

# We serve CSS files
Cuba.use Rack::Static, :urls => ["/css"], :root => "public"

# Include our own helpers
Cuba.plugin Helpers

Cuba.define do
  on root do
    render "index"
  end

  on "register" do
    on get do
      render "register"
    end

    on post do
      on param("username"), param("password") do |username, password|
        begin
          User.create(username: username, password: password)
          session[:success] = "Account created. You can log in now."
          redirect("/login")
        rescue Ohm::UniqueIndexViolation
          session[:error] = "Please choose a different username."
          redirect("/register")
        end
      end

      on true do
        session[:error] = "Missing credentials."
        redirect("/register")
      end
    end
  end

  on "private" do
    # From here on only for authenticated users.
    authenticated!

    on "keys" do
      on "add" do
        on post, param("response") do |response|
          u2f_response = U2F::RegisterResponse.load_from_json(response)

          reg = begin
                  u2f.register!(session[:challenges], u2f_response)
                rescue U2F::Error => e
                  session[:error] =  "Unable to register: #{e.class.name}"
                  redirect "/private/keys/add"
                ensure
                  session.delete(:challenges)
                end

          Registration.create(:certificate => reg.certificate,
                              :key_handle  => reg.key_handle,
                              :public_key  => reg.public_key,
                              :counter     => reg.counter,
                              :user        => current_user)


          session[:success] = "Key added."
          redirect "/private/keys"
        end

        on get do
          registration_requests = u2f.registration_requests
          session[:challenges] = registration_requests.map(&:challenge)

          render "key_add",
            registration_requests: registration_requests
        end
      end

      on true do
        keys = current_user.registrations
        render "keys", keys: keys
      end
    end

    on get do
      render "private"
    end
  end

  on "logout" do
    if authenticated(User)
      logout(User)
      session[:success] = "You are now logged out."
    end

    redirect("/")
  end

  on "login" do
    on "key" do
      on get do
        id = session[:user_prelogin].to_i
        redirect "/login" unless id > 0

        user = User[id]
        redirect "/login" unless user

        # Fetch existing Registrations from your db
        key_handles = user.registrations.map(&:key_handle)
        if key_handles.empty?
          session[:notice] = "Please add a key first."
          redirect "/private/keys"
        end

        # Generate SignRequests
        sign_requests = u2f.authentication_requests(key_handles)

        # Store challenges. We need them for the verification step
        session[:challenges] = sign_requests.map(&:challenge)
        render "login_key",
          sign_requests: sign_requests
      end

      on post, param("response") do |response|
        id = session[:user_prelogin].to_i
        redirect "/login" unless id > 0

        user = User[id]
        redirect "/login" unless user

        u2f_response = U2F::SignResponse.load_from_json(response)

        registration = user.registrations.find(key_handle: u2f_response.key_handle).first

        unless registration
          session[:error] = "No matching key handle found."
          redirect "/login"
        end

        begin
          u2f.authenticate!(session[:challenges], u2f_response,
                            Base64.decode64(registration.public_key), registration.counter.to_i)

        rescue U2F::Error => e
          session[:error] = "There was an error authenticating you: #{e}"
          redirect "/login"
        ensure
          session.delete(:challenges)
        end

        authenticate(user)
        registration.counter = u2f_response.counter
        registration.save
        session[:success] = "You are now logged in."
        redirect "/private"
      end
    end

    on get do
      redirect("/private") if authenticated(User)
      render "login"
    end

    on post do
      on param("username"), param("password") do |username, password|

        if login(User, username, password)
          if current_user.registrations.size > 0
            session[:notice] = "Please insert one of your registered keys to proceed."
            session[:user_prelogin] = current_user.id
            logout(User)
            redirect "/login/key"
          end

          session[:success] = "Successfully logged in."
          redirect(req.params["return"] || "/private")
        else
          session[:error] = "Wrong credentials."
          redirect "/login"
        end
      end

      on true do
        session[:error] = "Missing credentials."
        redirect "/login"
      end
    end
  end
end
