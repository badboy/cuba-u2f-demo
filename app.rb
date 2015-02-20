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

Cuba.plugin Cuba::Mote
Cuba.plugin Cuba::TextHelpers

Cuba.use Rack::Session::Cookie, :secret => "g+8oAKCmyJq46kjPmZ18nxCdcqeaujSIWu5p/Jl+h+0="

Cuba.plugin Shield::Helpers
Cuba.use Shield::Middleware, "/login"

Cuba.use Rack::Static, :urls => ["/css"], :root => "public"


Cuba.define do
  def u2f
    @u2f ||= U2F::U2F.new(req.base_url)
  end

  def error code
    halt [code, {}, []]
  end

  def current_user
    authenticated(User)
  end

  def authenticated!
    error(401) unless current_user
  end

  def redirect path
    res.redirect path
    halt res.finish
  end

  on root do
    @registration_requests = u2f.registration_requests
    session[:challenges] = @registration_requests.map(&:challenge)

    key_handles = Registration.all.map(&:key_handle)
    @sign_requests = u2f.authentication_requests(key_handles)

    flash = session[:flash]

    render "index",
      registration_requests: @registration_requests,
      sign_requests: @sign_requests
  end

  on "register" do
    on get do
      render "register"
    end

    on post do
      on param('username'), param('password') do |username, password|
        begin
          user = User.create(username: username, password: password)
          session[:success] = "Account created. You can log in now."
          res.redirect('/login')
        rescue Ohm::UniqueIndexViolation
          session[:error] = "Please choose a different username."
          res.redirect('/register')
        end
      end

      on true do
        session[:error] = "Missing credentials."
        res.redirect('/register')
      end
    end
  end

  on "private" do
    authenticated!

    on "keys" do
      on "add" do
        on post, param("response") do |response|
          u2f_response = U2F::RegisterResponse.load_from_json(response)

          reg = begin
                  u2f.register!(session[:challenges], u2f_response)
                rescue U2F::Error => e
                  session[:error] =  "Unable to register: #{e.class.name}"
                  res.redirect "/private/keys/add"
                ensure
                  session.delete(:challenges)
                end

          Registration.create(:certificate => reg.certificate,
                              :key_handle  => reg.key_handle,
                              :public_key  => reg.public_key,
                              :counter     => reg.counter,
                              :user        => current_user)


          session[:success] = "Key added."
          res.redirect "/private/keys"
        end

        on get do
          registration_requests = u2f.registration_requests
          session[:challenges] = registration_requests.map(&:challenge)

          key_handles = current_user.registrations.map(&:key_handle)
          sign_requests = u2f.authentication_requests(key_handles)

          render "key_add",
            registration_requests: registration_requests,
            sign_requests: sign_requests
        end
      end

      on true do
        keys = current_user.registrations
        render "keys", keys: keys
      end
    end

    on get do
      unless authenticated(User)
        session[:notice] = "Please login first."
        error(401)
      end

      render "private"
    end
  end

  on "logout" do
    if authenticated(User)
      logout(User)
      session[:success] = "You are now logged out."
    end

    res.redirect('/')
  end

  on "login" do
    on "key" do
      on get do
        id = session[:user_prelogin].to_i
        res.redirect "/login" unless id > 0

        user = User[id]
        res.redirect "/login" unless user

        # Fetch existing Registrations from your db
        key_handles = user.registrations.map(&:key_handle)
        if key_handles.empty?
          session[:notice] = "Please add a key first."
          res.redirect "/private/keys"
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
        res.redirect "/login" unless id > 0

        user = User[id]
        res.redirect "/login" unless user

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
      res.redirect('/private') if authenticated(User)

      render "login"
    end

    on post do
      on param('username'), param('password') do |username, password|

        if login(User, username, password)
          puts "@@@ " + current_user.registrations.size.to_s
          if current_user.registrations.size > 0
            session[:notice] = "Please insert one of your registered keys to proceed."
            session[:user_prelogin] = current_user.id
            logout(User)
            redirect "/login/key"
          end


          remember_me = false
          session[:success] = "Successfully logged in."
          remember(authenticated(User)) if remember_me
          res.redirect(req.params['return'] || '/private')
        else
          session[:error] = "Wrong credentials."
          res.redirect "/login"
        end
      end

      on true do
        #res.write "Parameters missing. Available: #{req.params}"
        session[:error] = "Missing credentials."
        res.redirect "/login"
      end
    end
  end

  on get do
    on "klogin" do
      key_handles = Registration.all.map(&:key_handle)
      if key_handles.empty?
        render "register_first"
        break
      end

      @sign_requests = u2f.authentication_requests(key_handles)
      session[:challenges] = @sign_requests.map(&:challenge)

      render "login", sign_requests: @sign_requests
    end

  end

  on post do
    on "registrations", param("response") do |response|
      u2f_response = U2F::RegisterResponse.load_from_json(response)

      reg = begin
              u2f.register!(session[:challenges], u2f_response)
            rescue U2F::Error => e
              res.write "Unable to register: #{e.class.name}"
              break
            ensure
              session.delete(:challenges)
            end

      puts "@@@ registrations. #{reg.inspect}"

      Registration.create(:certificate => reg.certificate,
                          :key_handle  => reg.key_handle,
                          :public_key  => reg.public_key,
                          :counter     => reg.counter)


      render "registration"
    end

    on "authentications", param("response") do |response|
      u2f_response = U2F::SignResponse.load_from_json(response)

      puts "Registration by key handle: #{u2f_response.key_handle}"
      registration = Registration.find(key_handle: u2f_response.key_handle).first
      puts "Registration: #{registration.public_key}"
      puts "@@@ #{registration.counter.inspect}"

      begin
        u2f.authenticate!(session[:challenges], u2f_response,
                          Base64.decode64(registration.public_key), registration.counter.to_i)

      rescue U2F::Error => e
        render "authfail", error: e
        break
      ensure
        session.delete(:challenges)
      end

      registration.counter = u2f_response.counter
      registration.save
      render "authenticated"
    end
  end
end
