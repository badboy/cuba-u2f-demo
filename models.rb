# encoding: utf-8

require "ohm"
require "ohm/contrib"
require "shield"

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

