#!/usr/bin/env ruby
require 'tempfile'
require 'base64'
require 'uri'
require 'net/http'
require 'openssl'
require 'json'
require 'cgi'
require 'fileutils'
require 'open3'

def dump_clipboard_image
    content = ''
    file = Tempfile.new ['alfred_ocr', '.jpg']
    begin
        file.close
        `./pngpaste/pngpaste #{file.path}`
        unless $?.success?
            raise 'No image found in your clipboard.'
        end
        content = Base64.encode64 file.open.read
    ensure
        file.unlink
    end

    if content.length > 4*1024*1024
        raise 'image should be smaller than 4M'
    end
    content
end

$credentials_file_folder = (ENV['alfred_workflow_data'] or ENV['HOME'])
$credentials_file_path = $credentials_file_folder + '/.alfred_ocr_credentials'

def clear_credentials
    begin
        FileUtils.rm $credentials_file_path
    rescue
    end
end

def get_credentials
    credentials = {}
    FileUtils.mkdir_p $credentials_file_folder
    api_key = ENV['bce_api_key']
    api_secret = ENV['bce_api_secret']
    begin
        File.open($credentials_file_path, 'r') do |file|
            credentials = Marshal.load file
        end
        if credentials['expires_at'] < Time.now
            raise 'Your credentials has expired'
        end
    rescue
        raise 'bce_api_key is not defined' unless api_key
        raise 'bce_api_secret is not defined' unless api_secret
        url = URI("https://aip.baidubce.com/oauth/2.0/token?grant_type=client_credentials&client_id=#{api_key}&client_secret=#{api_secret}")

        http = Net::HTTP.new(url.host, url.port)
        http.use_ssl = true
        http.verify_mode = OpenSSL::SSL::VERIFY_NONE

        request = Net::HTTP::Post.new(url)

        response = http.request(request)
        credentials = JSON.load response.read_body
        raise 'Credentials incorrect' unless credentials['expires_in']
        credentials['expires_at'] = Time.now + credentials['expires_in']
    end
    File.open($credentials_file_path, 'w') do |file|
        file.write(Marshal.dump credentials)
    end
    credentials
end

def ocr_text(image_base64, credentials)
    image_base64_encoded = CGI::escape image_base64
    access_token = credentials['access_token']

    url = URI("https://aip.baidubce.com/rest/2.0/ocr/v1/general_basic?access_token=#{access_token}")

    http = Net::HTTP.new(url.host, url.port)
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE

    request = Net::HTTP::Post.new(url)
    request["content-type"] = 'application/x-www-form-urlencoded'
    request.body = "image=#{image_base64_encoded}"

    response = http.request(request)
    data = JSON.load response.read_body
    raise 'Request failed' unless data['words_result']
    data['words_result'].map{|x| x['words']}.join "\n"
end

def generate_json(variables)
    obj = {
        'alfredworkflow' => {
            'arg' => 'something',
            'config' => {},
            'variables' => variables
        }
    }
    puts(JSON.dump obj)
end

begin
    image_base64 = dump_clipboard_image
    credentials = get_credentials
    result = ''
    times = 0
    begin
        result = ocr_text image_base64, credentials
    rescue
        clear_credentials
        times += 1
        retry if times <= 1
    end
    Open3.popen3( 'pbcopy' ){ |input, _, _| input << result }
    generate_json({
        'title' => 'Text Copied',
        'content' => result
    })
rescue Exception => e
    generate_json({
        'title' => 'OCR Clipboard Error',
        'content' => "#{e.message}"
    })
    STDERR.puts e
    STDERR.puts e.trace
end
