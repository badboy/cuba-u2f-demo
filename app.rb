#!/usr/bin/env ruby
# encoding: utf-8

require "cuba"
require "mote"
require "mote/render"
require "ohm"

Cuba.plugin(Mote::Render)

Cuba.define do
  def u2f
    @u2f ||= U2F::U2F.new(request.base_url)
  end

  on root do
    render "index"
  end
end
