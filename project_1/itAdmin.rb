require 'aws-sdk'
require 'yaml'
require_relative './ec2Instance.rb'

# 
# author: djiango
# 
# need ruby 2.0
# 
# to install the SDK and lib, run `sudo gem install aws-sdk`
# 
# to run the script, run `ruby itAdmin.rb`
# 

# initialize
# this config.yml file should your contain the access_key_id and 
# secret_access_key
config_file = './config.yml'
config = YAML.load(File.read(config_file))
AWS.config(config)
users = Array.new
adminInstances = Array.new
instances = key_pair = group = nil
shutdown_number = 0

config['users'].each do |user|
  users.push(user)
end


# Script start
puts 'Script begin ......'

# create an agent
ec2 = AWS::EC2.new(:region => "us-west-2")
@cw = AWS::CloudWatch.new(:region => "us-west-2")
s3 = AWS::S3.new(:region => "us-west-2")

#
# Start ! !
#

# key_pair
unless ec2.key_pairs['itAdminKey'].exists? && File.exist?('./itAdminKey.pem')
  File.delete('./itAdminKey.pem') if File.exist?('./itAdminKey.pem')
  ec2.key_pairs['itAdminKey'].delete if ec2.key_pairs['itAdminKey'].exists?

  # generate a key pair
  key_pair = ec2.key_pairs.create('itAdminKey')
  puts "Generated a new keypair #{key_pair.name}, 
        fingerprint: #{key_pair.fingerprint}"

  # download the key
  File.open("./#{key_pair.name}.pem", "wb") do |f|
    f.write(key_pair.private_key)
  end
  puts "Download the key pair to local folder, ./#{key_pair.name}.pem."
  puts "Using security key pair: #{key_pair.name}"
else
  key_pair = ec2.key_pairs['itAdminKey'];
  puts "Using security key pair: #{key_pair.name}"
end


# security group
if ec2.security_groups.filter('group-name', 'itAdminGroup').first.nil?
  group = ec2.security_groups.create("itAdminGroup")
  # ssh port
  group.authorize_ingress(:tcp, 22)
  # http port
  group.authorize_ingress(:tcp, 80)
  puts "Generated a new security group"
else
  group = ec2.security_groups.filter('group-name', 'itAdminGroup').first
  puts "Using security group: #{group.name}"
end

# new manager object
users.each do |user|
  volume_name = "itAdminKey_volume_#{user['id']}"
  if (snapshot = ec2.snapshots
        .filter('description', volume_name).first).nil?
    volume = ec2.volumes.create(:size => 3, 
                                :availability_zone => "us-west-2a")
  else
    volume = snapshot.create_volume('us-west-2a')
  end
  ins = Ec2Instance.new(ec2, user['id'], key_pair,
                          group, volume, user['ip'])
  adminInstances.push(ins)
end

# run every instance
adminInstances.each { |ins| ins.createAndRun }

p 'Everything is go to gooooooood!!!!'


def cpuMonitor(instance_id)
  metric = @cw.metrics.filter('namespace', 'AWS/EC2')
          .filter('metric_name', 'CPUUtilization')
          .with_dimensions([{:name => 'InstanceId', 
                            :value => instance_id}]).first
  return false if metric == nil

  stats = metric.statistics(:start_time => Time.now - 600,
                           :end_time => Time.now,
                           :period => 600,
                           :statistics => ['Average'])
  cpuUtil = stats.datapoints.first[:average]
  p "#{instance_id}'s CPU Utilization is #{cpuUtil}%..."
  return cpuUtil
end


# start watch
while (Time.now.hour < 17 && adminInstances.count > shutdown_number)
  adminInstances.each do |ins|
    p "Check instance #{ins.giveMeinstanceId}'s the CPU ..."
    next unless cpuMonitor(ins.giveMeinstanceId)
    if (ins.alive? && (cpuMonitor(ins.giveMeinstanceId) < 5))
      ins.terminateMe
      shutdown_number += 1
    end
  end
  p "Time is #{Time.now}."
  p "#{adminInstances.count - shutdown_number} still running.."
  p "Sleep for 60 seconds."
  sleep 60
end

# clean up
adminInstances.each do |ins|
  if (ins.alive?)
    ins.terminateMe
  end
end

# use S3 as log system
unless (bucket = s3.buckets['admin.log.assignment']).exists?
  bucket = s3.buckets.create('admin.log.assignment')
end
time = Time.now
obj = bucket.objects.create("log_#{time}", "Running completed #{time}.")

p obj.read

p 'finish!!!!...hahahaha...!!!!!'
