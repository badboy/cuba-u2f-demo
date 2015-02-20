# encoding: utf-8

require "ohm"
require "ohm/contrib"
require "shield"

# Our key registration data.
#
# Each key has a key handle, that is sent to the client,
# so it can pick the right key.
#
# The public key is used for checking the signatures.
# The certificate is currently not checked for validity.
#
# To avoid replay attacks we save the counter and check
# that each new signature is generated with a not-yet-seen counter.
#
# Each Registration belongs to a user.
class Registration < Ohm::Model
  include Ohm::Timestamps
  include Ohm::DataTypes

  attribute :key_handle
  index :key_handle

  attribute :public_key
  attribute :certificate
  attribute :counter

  reference :user, :User
end

# Simplest viable User structure, only a name and a password.
class User < Ohm::Model
  include Shield::Model

  attribute :username
  unique :username

  attribute :crypted_password

  collection :registrations, :Registration

  def self.fetch(identifier)
    with(:username, identifier)
  end
end

