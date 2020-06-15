# frozen_string_literal: true

require 'net/http'
require 'base64'

require 'tus/client/version'

module Tus
  class Client
    # 100 MiB is ok for now...
    CHUNK_SIZE = 100 * 1024 * 1024
    TUS_VERSION = '1.0.0'

    def initialize(server_url)
      @server_uri = URI.parse(server_url)

      # better to open the connection now
      @http = Net::HTTP.start(@server_uri.host, @server_uri.port)
      # we cache this value for further use
      @capabilities = capabilities
    end

    def upload(file_path)
      raise 'No such file!' unless File.file?(file_path)

      io = File.open(file_path, 'rb')

      uri = create_remote(File.basename(file_path), File.size(file_path))

      io.close
    end

    private

    def capabilities
      raise 'Uninitialized connection!' unless @http

      response = @http.options(@server_uri.request_uri)

      response['Tus-Extension']&.split(',')
    end

    def create_remote(file_name, file_size)
      unless @capabilities.include?('creation')
        raise 'New file uploading not supported!'
      end

      request = Net::HTTP::Post.new(@server_uri.request_uri)
      request['Content-Length'] = 0
      request['Upload-Length'] = file_size
      request['Tus-Resumable'] = TUS_VERSION
      request['Upload-Metadata'] = "filename: #{Base64.strict_encode64(file_name)},is_confidential"

      response = @http.request(request)

      unless response.is_a?(Net::HTTPCreated)
        raise 'Cannot create a remote file!'
      end

      response['Location']
    end

    def file_offset(file_uri); end

    def upload_chunk(file_uri, io); end
  end
end
