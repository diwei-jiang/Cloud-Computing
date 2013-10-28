class Ec2Instance

  def initialize(ec2, id, key_pair, group, volume, static_ip)
    @alive = true
    @ec2 = ec2
    @id = id
    @key_pair = key_pair
    @group = group
    @ami_name = "adminAMI_#{@id}"
    @volume = volume
    @static_ip = static_ip
    @instance = nil
    if @ec2.images.filter('name', @ami_name).first.nil?
      @ami = nil
    else
      @ami = @ec2.images.filter('name', @ami_name).first
    end
  end

  # for testing
  def load(instance_id)
    @instance = @ec2.instances[instance_id]
  end

  # create one and run one, so much fun!
  def createAndRun
    puts "Start initialize instance #{@id}...."
    if @ami.nil?
      createInstance()
    else
      createInstance(@ami.id)
    end
    attachVolume()
    allocateStaticIp()
    puts "instance #{@id} is good to go!"
  end

  # launch the instance (ubuntu 12.04) by default
  def createInstance (image_id = 'ami-70f96e40')
    @instance = @ec2.instances.create(:count => 1,
                                      :availability_zone => 'us-west-2a',
                                      :image_id => image_id,
                                      :key_pair => @key_pair,
                                      :security_groups => @group,
                                      :instance_type => 't1.micro')
    puts "instance create successful, waiting for running....."
    sleep 5 while @instance.status == :pending
    puts "Launched instance #{@instance.id}, status: #{@instance.status}"
  end

  # give instance static ip
  def allocateStaticIp
    puts "allocate static ip #{@static_ip}..."
    @instance.associate_elastic_ip(@ec2.elastic_ips[@static_ip])
  end

  # create volume for user
  def attachVolume
    sleep 5 unless @volume.status == :available
    attachment = @volume.attach_to(@instance, '/dev/sdf')
    sleep 1 until attachment.status != :attaching
  end

  # start distory process
  def terminateMe
    puts "terminating instance #{@id} start..."
    # if first time, then nothing to delete
    unless @ami.nil?
      # cache snapshot_id
      old_snapshots = Array.new
      @ami.block_device_mappings.each do |key, value|
        old_snapshots.push(value[:snapshot_id])
      end
      # delete ami
      p "deleting old ami..."
      @ami.delete
      sleep 1 unless @ec2.images.filter('name', @ami_name).first.nil?
      # delete snapshot
      p "deleting old snapshots..."
      old_snapshots.each do |snapshot_id|
        @ec2.snapshots[snapshot_id].delete
      end
    end

    # detach volume
    p 'detaching the volumes...'
    @volume.attachments.each do |attachment|
      attachment.delete(:force => true)
    end
    sleep 1 until @volume.status == :available

    # delete old snapshot
    unless (snapshot = @ec2.snapshots
        .filter('description', "itAdminKey_volume_#{@id}").first).nil?
      snapshot.delete
    end
    # create new snapshot
    snapshot = @volume.create_snapshot("itAdminKey_volume_#{@id}")
    sleep 1 until snapshot.status == :completed
    # delete volume
    @volume.delete

    # new ami
    p 'Creating the new ami...'
    new_ami = @instance.create_image(@ami_name, :no_reboot => false)
    sleep 5 while new_ami.state != :available
    p "a new ami has been created, with id #{new_ami.id}"

    p 'deleting the instance...'
    @instance.delete
    sleep 10 while @instance.status != :terminated
    @alive = false
  end

  def giveMeinstanceId
    @instance.id
  end

  def alive?
    @alive
  end
end