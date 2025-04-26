require "droplet_kit"

module Kitsune
  module Kit
    class Provisioner
      def initialize(opts)
        @droplet_name = opts[:droplet_name]
        @region       = opts[:region]
        @size         = opts[:size]
        @image        = opts[:image]
        @tag          = opts[:tag]
        @ssh_key_id   = opts[:ssh_key_id] do
          abort "❌ You must export SSH_KEY_ID or use --ssh_key_id"
        end

        @client       = DropletKit::Client.new(access_token: ENV.fetch("DO_API_TOKEN"))
      end
  
      # Find an existing droplet by name
      def find_droplet
        @client.droplets.all(tag_name: @tag).detect { |d| d.name == @droplet_name }
      end
  
      # Create command: shows if it exists or creates a new one
      def create_or_show
        if (d = find_droplet)
          ip = public_ip(d)
          puts "✅ Droplet '#{@droplet_name}' already exists (ID: #{d.id}, IP: #{ip})"
        else
          puts "✍🏻 Creating Droplet '#{@droplet_name}'..."
          spec = DropletKit::Droplet.new(
            name:       @droplet_name,
            region:     @region,
            size:       @size,
            image:      @image,
            ssh_keys:   [@ssh_key_id],
            tags:       [@tag]
          )
          created = @client.droplets.create(spec)
          wait_for_status(created.id)
          ip = wait_for_public_ip(created.id)

          wait_for_ssh(ip)
  
          puts "✅ Droplet created: ID=#{created.id}, IP=#{ip}"
        end
      end
  
      # Rollback command: deletes it if it exists
      def rollback
        if (d = find_droplet)
          puts "🔁 Deleting Droplet '#{@droplet_name}' (ID: #{d.id})..."
          @client.droplets.delete(id: d.id)
          puts "✅ Droplet deleted 💥"
        else
          puts "✅ Nothing to delete: '#{@droplet_name}' does not exist"
        end
      end
  
      private
  
      # Extracts the public IP from a DropletKit::Droplet
      def public_ip(droplet)
        v4 = droplet.networks.v4.find { |n| n.type == "public" }
        v4 ? v4.ip_address : "(no public IP yet)"
      end

      # Waits until the droplet reaches the 'active' status
      def wait_for_status(droplet_id, interval: 5, max_attempts: 24)
        max_attempts.times do |i|
          droplet = @client.droplets.find(id: droplet_id)
          estado = droplet.status
          puts "⏳ Droplet status: #{estado} (#{i + 1}/#{max_attempts})"
          return if estado == "active"
          sleep interval
        end
        abort "❌ Timeout: the Droplet did not reach 'active' status after #{interval * max_attempts} seconds"
      end

      # Waits until obtaining the public IP
      def wait_for_public_ip(droplet_id, interval: 5, max_attempts: 24)
        max_attempts.times do |i|
          droplet = @client.droplets.find(id: droplet_id)
          if (v4 = droplet.networks.v4.find { |n| n.type == "public" })
            return v4.ip_address
          end
          puts "⏳ Waiting for public IP... (#{i + 1}/#{max_attempts})"
          sleep interval
        end
        abort "❌ Timeout: the Droplet did not obtain a public IP after #{interval * max_attempts} seconds"
      end

      # Waits for the SSH port to become accessible
      def wait_for_ssh(ip, interval: 5, max_attempts: 24)
        max_attempts.times do |i|
          begin
            puts "🔐 Waiting for SSH connection to #{ip}... (#{i + 1}/#{max_attempts})"
            TCPSocket.new(ip, 22).close
            puts "🔓 SSH connection to #{ip} established"
            return
          rescue Errno::ECONNREFUSED, Errno::ETIMEDOUT, SocketError
            sleep interval
          end
        end
        abort "❌ Could not connect via SSH to #{ip} after #{interval * max_attempts} seconds"
      end
    end
  end
end
