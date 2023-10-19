#!/bin/bash

#assign variables
file="Vagrantfile"

#create a directory where the script will be executed
mkdir -p ~/segunassignment

#Change directory to the directory you created
cd ~/segunassignment

#initalize vagrant to pull a vagrantfile
vagrant init ubuntu/focal64

#delete the last line of the file and edit the file
sed -i '$ d' Vagrantfile

#EDIT THE VAGRANT FILE TO ADD MASTER AND SLAVE
#multi-machine setup
#setup master
cat << EOL >> $file

config.vm.define "Master" do |master|
 master.vm.box = "ubuntu/focal64"
 master.vm.hostname = "Master"
 master.vm.network "private_network", type: "dhcp"
end
EOL

#setup slave

cat << EOL >> $file

config.vm.define "Slave" do |slave|
 slave.vm.box = "ubuntu/focal64"
 slave.vm.hostname = "slave"
 slave.vm.network "private_network", type: "dhcp"
end
end
EOL

#bring up the machines
vagrant up

slave_ip=$(vagrant ssh Slave -c "ip addr show enp0s8 | grep -oP '(?<=inet\s)\d+(\.\d+){3}'" | tr -d '\r')

vagrant ssh Master -c "echo \"#!/bin/bash

# Update the package list
sudo apt update

# Install Apache web server
sudo apt install -y apache2

# Enable Apache to start on boot
sudo systemctl enable apache2

# Start the Apache service
sudo service apache2 start

# Install MySQL Server
sudo apt install -y mysql-server

#secure mysql installation
sudo mysql_secure_installation <<EOF

n
y
y
y
y
EOF

# Install PHP and required modules
sudo apt install -y php libapache2-mod-php php-mysql

# Clone the PHP application from GitHub
cd /var/www/html
sudo git clone https://github.com/laravel/laravel

# Configure Apache to serve the PHP application
sudo mv /var/www/html/laravel /var/www/html/app
sudo chown -R www-data:www-data /var/www/html/app

sudo chmod -R 755 /var/www/html/app\" > script.sh"

echo "
in_slave_ip=\$(ip addr show enp0s8 | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | tr -d '\r')" >> script.sh

echo "
# Create a virtual host configuration for the PHP application
cat << EOF | sudo tee /etc/apache2/sites-available/app.conf
<VirtualHost *:80>
    ServerAdmin webmaster@localhost
    DocumentRoot /var/www/html/app
    ServerName \$in_slave_ip
    DirectoryIndex /resources/views/welcome.blade.php

    ErrorLog ${APACHE_LOG_DIR}/error.log
    CustomLog ${APACHE_LOG_DIR}/access.log combined
</VirtualHost>
EOF
" >> script.sh

cat script.sh | vagrant ssh Master -c "cat >> script.sh"

vagrant ssh Master -c "echo \"
# Enable the virtual host
sudo a2ensite app

# Restart Apache to apply PHP changes
sudo service apache2 restart\" >> script.sh"

vagrant ssh Master -c "chmod 777 script.sh"

#create ssh key for master node as altschool user
vagrant ssh Master -c "ssh-keygen -f ~/.ssh/id_rsa -N ''"

#set up ssh config for slave hostname in master
#vagrant ssh Master -c "echo -e \"Host slave\n\tHOSTNAME $slave_ip\n\tUser vagrant\" > ~/.ssh/config"

#copy public key from master to authorized keys in slave
vagrant ssh Master -c "cat ~/.ssh/id_rsa.pub" | vagrant ssh Slave -c "cat >> ~/.ssh/authorized_keys"

echo "[slave]
$slave_ip" > inventory

cat inventory | vagrant ssh Master -c "cat > inventory.ini"

vagrant ssh Master -c "sudo apt update -y && sudo apt install ansible -y"

vagrant ssh Master -c "touch random"

vagrant ssh Master -c "scp -o StrictHostKeyChecking=no random vagrant@$slave_ip:~/"

vagrant ssh Master -c "echo \"---
- name: Execute Script on Slave
  hosts: slave
  become: yes  # This allows running commands with elevated privileges

  tasks:
    - name: Copy the Bash script to the slave machine
      copy:
        src: script.sh  # Replace with the actual path to your script
        dest: ~/script.sh  # Replace with the desired path on the slave
      register: script_copy_result

    - name: Execute the Bash script on the slave machine
      command: bash ~/script.sh
      when: script_copy_result.changed  # Only execute if the script was copied\" > script_playbook.yml"

vagrant ssh Master -c "ansible-playbook -i inventory.ini script_playbook.yml"
