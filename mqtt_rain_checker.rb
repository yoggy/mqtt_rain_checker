#!/usr/bin/ruby
# vim: ts=2 sw=2 et si ai :

require 'pp'
require 'mqtt'
require 'logger'
require 'yaml'
require 'ostruct'
require 'json'
require 'date'

def usage
  $stderr.puts "usage : #{File.basename($0)} config.yaml"
  exit(1)
end

$stdout.sync = true
Dir.chdir(File.dirname($0))
$current_dir = Dir.pwd

$log = Logger.new(STDOUT)
$log.level = Logger::DEBUG

$last_rainy_pixel_count = 0

usage if ARGV.size == 0

$conf = OpenStruct.new(YAML.load_file(ARGV[0]))

$conn_opts = {
  remote_host: $conf.mqtt_host,
  client_id: $conf.mqtt_client_id
}

if !$conf.mqtt_port.nil?
  $conn_opts["remote_port"] = $conf.mqtt_port
end

if $conf.mqtt_use_auth == true
  $conn_opts["username"] = $conf.mqtt_username
  $conn_opts["password"] = $conf.mqtt_password
end

def main_loop
  $log.info "connecting..."
  MQTT::Client.connect($conn_opts) do |c|
    $log.info "connected!"

    c.subscribe($conf.subscribe_topic)

    c.get do |topic, message|
      $log.info "recv: topic=#{topic}, message=#{message}"
      $last_received_time = Time.now

      json = JSON.parse(message)
      now_count = json["rainy_pixel_count"]

      if now_count != $last_rainy_pixel_count && now_count >= $conf.rainy_pixel_threshold
        $log.info "rainy_pixel count is greater than #{$conf.rainy_pixel_threshold}"

        h = Time.now.hour
        h += 24 if h < 5  # 5-29
        
        if $conf.start_time <= h && h <= $conf.end_time
          $log.info "publish : topic=#{$conf.publish_topic}, payload=#{$conf.rainy_alert_message}"
          c.publish($conf.publish_topic, $conf.rainy_alert_message)
        end
      end

      $last_rainy_pixel_count = now_count
    end
  end
end

loop do
  begin
    main_loop
  rescue Exception => e
    $log.debug(e.to_s)
  end

  begin
    Thread.kill($watchdog_thread) if $watchdog_thread.nil? == false
    $watchdog_thread = nil
  rescue
  end

  $log.info "waiting 5 seconds..."
  sleep 5
end
