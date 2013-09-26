require 'aws-sdk'
require 'yaml'
require 'net/ssh'

# 
# author: Diwei Jiang
# email:  dj815@nyu.edu
# 
# need ruby 2.0
# 
# to install the SDK and lib, run `sudo gem install aws-sdk net-ssh`
# 
# to run the script, run `ruby createNewEC2Instance.rb`
# 


# initialize
# this config.yml file should your contain the access_key_id and secret_access_key
config_file = './config.yml'
config = YAML.load(File.read(config_file))
AWS.config(config)
instance = key_pair = group = nil

# Script start
puts 'Script begin ......'

# create an agent
ec2 = AWS::EC2.new(:region => "us-west-2")

# generate a key pair
key_pair = ec2.key_pairs.create("auto-ruby-#{Time.now.to_i}")
puts "Generated a new keypair #{key_pair.name}, fingerprint: #{key_pair.fingerprint}"

# download the key
File.open("./#{key_pair.name}.pem", "wb") do |f|
  f.write(key_pair.private_key)
end
puts "Download the key pair to local folder, ./#{key_pair.name}.pem."

# security group
if (group = ec2.security_groups.filter("group-name", "auto-ruby").first).nil?
  group = ec2.security_groups.create("auto-ruby")
  # ssh port
  group.authorize_ingress(:tcp, 22)
  # http port
  group.authorize_ingress(:tcp, 80)
  # for tcp call
  group.authorize_ingress(:tcp, 54321)
  # rails port, for fun
  group.authorize_ingress(:tcp, 3000)
  puts "Generated a new security group"
end
puts "Using security group: #{group.name}"


# launch the instance (ubuntu 12.04), 
instance = ec2.instances.create(:count => 1,
                                :image_id => 'ami-70f96e40',
                                :key_pair => key_pair,
                                :security_groups => group,
                                :instance_type => 't1.micro')

# add a tag(name) to new instance
instance.add_tag("Name", :value => "auto_ruby_instance")

puts "instance create successful, waiting for running....."
# wait for the instance start
sleep 10 while instance.status == :pending
puts "Launched instance #{instance.id}, status: #{instance.status}"
exit 1 unless instance.status == :running



puts "Start ssh process....."
# ssh into the instance
begin
  Net::SSH.start(instance.ip_address, "ubuntu", :key_data => key_pair.private_key, :timeout => 20) do |ssh|
    puts "Welcome to fake ssh terminal....(standard test case 'ls -al', 'exit' for exit)"
    begin
      print "ubuntu?> "; STDOUT.flush; str = gets.chop
      puts ssh.exec!(str) if str!=""
    end while str!="exit" 
    puts "bye bye ~"
  end
rescue SystemCallError, Timeout::Error => e
  # port 22 might not be available immediately after the instance finishes launching
  sleep 1
  retry
end