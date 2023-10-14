#!/bin/bash

#assign variables
file="Vagrantfile"

#create a directory where the script will be executed
mkdir -p ~/vagranttask

#Change directory to the directory you created
cd ~/vagranttask

#initalize vagrant to pull a vagrantfile
vagrant init ubuntu/focal64

#delete the last line of the file and edit the file
sed -i '$ d' Vagrantfile

#EDIT THE VAGRANT FILE TO ADD MASTER AND SLAVE

#multi-machine setup
#setup master
cat << EOL >> $file

config.vm.define "master" do |subconfig|
 subconfig.vm.box = "ubuntu/focal64"
 subconfig.vm.hostname = "master"
 subconfig.vm.network "private_network", type: "dhcp"
end
EOL

#setup slave

cat << EOL >> $file

config.vm.define "slave" do |subconfig|
 subconfig.vm.box = "ubuntu/focal64"
 subconfig.vm.hostname = "slave"
 subconfig.vm.network "private_network", type: "dhcp"
end
end
EOL

#bring up the machines
vagrant up

#create a user 'altschool and grant root priveleges
vagrant ssh master -c "sudo useradd -m -s /bin/bash -G sudo altschool"

#adding altschool to sudoers file
vagrant ssh master -c 'echo -e "\naltschool ALL=(ALL:ALL) NOPASSWD: ALL\n" | sudo tee -a /etc/sudoers'

#adding password
vagrant ssh master -c 'echo -e "12345\n12345" | sudo passwd altschool'

#create ssh key for master node as altschool user
vagrant ssh master -c "sudo -u altschool ssh-keygen -t rsa -b 2048 -f /home/altschool/.ssh/id_rsa -N ''"

#get the ip address of slave
slave_ip=$(vagrant ssh slave -c "ip addr show enp0s8 | grep -oP '(?<=inet\s)\d+(\.\d+){3}'" | tr -d '\r')

#set up ssh config for slave hostname in master
vagrant ssh master -c "sudo -u altschool bash -c 'echo -e \"Host slave\n\tHOSTNAME $slave_ip\n\tUser vagrant\" > ~/.ssh/config'"

#you can now ssh into the slave from the machine using
#ssh slave. or access the slave machine via just slave

#copy public key from master to authorized keys in slave
vagrant ssh master -c "sudo -u altschool cat /home/altschool/.ssh/id_rsa.pub" | vagrant ssh slave -c "cat >> ~/.ssh/authorized_keys"

#create content in altschool master
vagrant ssh master -c "sudo -u altschool sudo mkdir -p /mnt/altschool"

vagrant ssh master -c "sudo -u altschool sudo touch /mnt/altschool/newfile /mnt/altschool/oldfile /mnt/altschool/ranfile"

#make directory in slave
vagrant ssh slave -c "sudo mkdir -m 777 -p /mnt/altschool/slave"

#move content to slave from master
vagrant ssh master -c "sudo -u altschool scp -o StrictHostKeyChecking=no -r /mnt/altschool/* slave:/mnt/altschool/slave"
