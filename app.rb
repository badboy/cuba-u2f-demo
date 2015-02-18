#!/usr/bin/env ruby
# encoding: utf-8

require "cuba"

Cuba.define do
  on root do
    res.write("Hello Frogger!")
  end
end
