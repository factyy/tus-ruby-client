# frozen_string_literal: true

require 'tus/client/version'

require 'net/http'

module Tus
  class Client
    def initialize(server_url)
      @server_uri = URI.parse(server_url)

      @http = Net::HTTP.new(@server_uri.host, @server_uri.port)
      @capabilities = capabilities # we cache this value for further use
    end

    def upload(file_path)
      raise 'New file uploading not supported!' unless file_exists?(file_path) || @capabilities.include?('creation')

      create_remote(file_path) unless file_exists?(file_path)
    end

    private

    def capabilities
      raise 'Uninitialized connection!' unless @http

      response = @http.options(@server_uri.request_uri)

      response['Tus-Extension']&.split(',')
    end

    def file_exists?(file_path); end

    def create_remote(file_path); end

    def file_offset(file_path); end

    def resume_upload(file_path); end
  end
end
