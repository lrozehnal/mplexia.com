+++
date = '2026-07-12T14:57:02+02:00'
draft = false
title = 'Building My CKA Lab'
+++

After messing around with Terraform and AWS for a while, I decided to shift the gear a bit and start preparing for the Certified Kubernetes Administrator (CKA) exam. I wanted to get a hands-on experience with Kubernetes and understand how it works under the hood. I got previous exposure to kubernetes but I mainly worked with docker and docker-swarm. So generally speaking I am more than familiar but I've never really did a deep dive into kubernetes and its components. I wanted to change that and get a better understanding of how it works. 

So the plan is following:

1) Get my onpremise kubernetes lab up and running
2) Get into CKA blueprint and start learning the topics
3) Start practicing with the lab and try to solve the exercises from the CKA exam
4) Get familiar with typical scenarios and ... introduce terraform and AWS EKS and AWS ECS and helm and all the other cool stuff
5) ???
6) Profit ... I mean passing the CKA exam 

## The lab

Historically I have this fairly old server running somewhere and I used it as a lab - somehow there was always this 'need' to spinup a pseudo-random VM / ISO of something and play around with it.  Those were the times I was using ansible heavily so this rebuild could be a nice exercise to undust ansible a bit as well. The physical host has 128GB of RAM so I would go for 8 virtual servers in total - three (3) as k8s controllers / control-plane and five (5) as regular workers so I can play with all the tainting and so on.... 

### Topology

For the topology, I have my main 'l4' server which act as default gateway (ip routing and NAT-wise), I do run DHCPD and DNS (bind) server there as well, plus Squid proxy. Historically I went through a lots of pain using various approaches to IP Plannening (IPAM) so my pick is following:
There's a DHCP range congigured within 10.199.0.0/24 IP subnet. Main 'l4' server has IP address 10.199.0.1 and IP addresses 10.199.0.10-10.199.0.249 are statically reserved to mac adddresses 00:00:00:00:00:10 - 00:00:00:00:02:49; 
If the new box got 'other' mac address, it will get IP address from 10.199.0.250-254; but the general idea is to a) setup static mac address on the VM and b) configure a record into bind's configuration file (which therefore act as an inventory what's there / what's used etc). And because of this, the server will be dynamically configured with statically setup IP address and DNS record. This is a nice approach because I can easily re-create the lab and I don't have to worry about IP addresses and DNS records.

## Ansible &  Ansible workflow

For ansible, I do have a separate 'ae' server which is running ansible and I will use it to configure the lab. As I played with ansible a bit, there are all those various playbooks over course of time, which is likely no longer working as but I can use it as a source of inspirtions... 

I like breaking the whole workflow into smaller (numbered) pieces, and ideally add snapshots so I can easily go back if something goes wrong. So the workflow is following:
01 - provision the VM 
02 - basic configuration and update of the VM 
03 - make an initial snapshot
04 - configure for k8s 
05 - initiate the cluster 
06 - join the cluster 
07 - make a k8s snapshot
xx - STUFF
91 - go back to k8s snapshot
92 - go back to initial snapshot
99 - decommision it all 


### 01 - inital provissioning

it seems the right way how to provision VMs is a [collection of 'community.vmware' ](https://docs.ansible.com/projects/ansible/latest/collections/community/vmware/index.html)

```yaml ( 01_provision.yaml )
- name: Create VM on my vmware vcenter.lab
  hosts: localhost
  gather_facts: no

  collections:
  - community.vmware

  tasks:
  - name: "Provission each VM"
    ansible.builtin.include_tasks: included_vm_provissioning.yaml
    loop: "{{ VMs }}"
    loop_control:
      loop_var: item
      label: "{{ item.name }}"

```

in here I want to look through the list of VMs and for each one, I will call a separate task file which will do the actual provissioning. The thing is that I'd like this to be run in strictly sequence way

```yaml ( included_vm_provissioning.yaml )
- name: Announce the task on the servers
  ansible.builtin.debug:
    msg: " Starting the tasks for provissioning of {{ item.name }} server !!"


- name: Create VMs from a template
  community.vmware.vmware_guest:
    hostname: "{{ vcenter_hostname }}" 
    username: "{{ vcenter_username }}"
    password: "{{ vcenter_password }}"
    validate_certs: no  
    datacenter: "{{ datacenter }}" 
    folder: "{{ vm_folder }}" 
    name: "{{ item.name }}"
    template: "{{ item.template | default(default_template) }}"
    state: present
    networks: []
    hardware:
      memory_mb: "{{ item.ram | default(default_ram) }}"  
      num_cpus: "{{ item.cpu | default(default_cpu) }}"
    resource_pool: "{{ resource_pool }}"

- name: Remove existing NIC from VM
  community.vmware.vmware_guest_network: 
    hostname: "{{ vcenter_hostname }}" 
    username: "{{ vcenter_username }}" 
    password: "{{ vcenter_password }}" 
    validate_certs: no 
    datacenter: "{{ datacenter }}" 
    name: "{{ item.name }}"
    mac_address: "{{ default_mac }}"
    state: absent

- name: Add NIC with custom MAC address
  community.vmware.vmware_guest_network: 
    hostname: "{{ vcenter_hostname }}" 
    username: "{{ vcenter_username }}" 
    password: "{{ vcenter_password }}" 
    validate_certs: no 
    datacenter: "{{ datacenter }}" 
    name: "{{ item.name }}" 
    state: present
    network_name: "{{ network }}"
    mac_address: "{{ item.mac }}"
    device_type: "vmxnet3"

- name: Power the VM on
  vmware.vmware.vm_powerstate:
    hostname: "{{ vcenter_hostname }}" 
    username: "{{ vcenter_username }}" 
    password: "{{ vcenter_password }}" 
    validate_certs: no 
    datacenter: "{{ datacenter }}" 
    name: "{{ item.name }}" 
    state: powered-on

- name: Announce the task on the servers
  ansible.builtin.debug:
    msg: "!! Provissioning COMPLETED for {{ item.name }} server !!"

```

As expected, one can't change the mac-address so the trick (which I've been using for years) is to remove the existing NIC and add a new one with the desired mac-address. (the statically configured well-known mac-address will guarantee a pre-defined IP address)

I am using `community.vmware.vmware_guest_network` module to remove and add NICs, and `community.vmware.vmware_guest` module to create the VM from a template. The template is some debian distribution linux, the local ssh key is pre-authorized already so my ansible won't have any issue when connecting to it later. This is group_vars/all.yaml file: 

```yaml ( group_vars/all.yaml )
vcenter_hostname: "{{ lookup('env', 'VMWARE_HOST') }}"
vcenter_username: "{{ lookup('env', 'VMWARE_USER') }}"
vcenter_password: "{{ lookup('env', 'VMWARE_PASSWORD') }}"
vmware_validate_certs: false
default_mac: "00:00:00:00:02:50"
default_cpu: 4
default_ram: 16384

datacenter: "lab"
default_template: "s0"
network: "Internal-admin"
resource_pool: "Resources"
vm_folder: ""

VMs:
  - name: "s1"
    mac: "00:00:00:00:00:11"
    ip: "10.199.0.11"
  - name: "s2"
    mac: "00:00:00:00:00:12"
    ip: "10.199.0.12"
  - name: "s3"
    mac: "00:00:00:00:00:13"
    ip: "10.199.0.13"
  - name: "s4"
    mac: "00:00:00:00:00:14"
    ip: "10.199.0.14"
  - name: "s5"
    mac: "00:00:00:00:00:15"
    ip: "10.199.0.15"
  - name: "s6"
    mac: "00:00:00:00:00:16"
    ip: "10.199.0.16"
  - name: "s7"
    mac: "00:00:00:00:00:17"
    ip: "10.199.0.17"
  - name: "s8"
    mac: "00:00:00:00:00:18"
    ip: "10.199.0.18"
```

Another trick about vcenter creds - as I am going to publish the code to public github and despite of facts that a) vcenter is stricly private and b) the username:password is something real silly like admin:admin, due to certain 'standards' (always make the efford and never pushlish your creds to public github) I will not hardcode the vcenter credentials into the code but I will use environment variables instead. At the same time I am a lazy person so I'd like to store those somewhere very handy and use those easily. And so:
I do have .helper file with those creds within the directory; inside .gitignore I have a line excluding the file .helper from being pushed to git but when I want to run it, I can easily make the content of the .helper file the system variables
```bash (.helper)
export VMWARE_HOST="silly.lab"
export VMWARE_USER="sillyadmin"
export VMWARE_PASSWORD="sillypassword"
```
```bash
. .helper
```
and when I run my ansible, the values will be read from the just-loaded-system variables... pretty handy right?

### 02 - basic configuration
```yaml ( 02_initial_setup_of_VMs.yaml )
- name: Post-provissioning setup
  hosts: k8s-all
  gather_facts: no
  become: yes
  serial: 100%
  tasks:
  - name: Setup servername
    become: yes
    ansible.builtin.hostname:
      name: "{{ inventory_hostname }}"  
    register: hostname_result

  - name: Update atp cache
    ansible.builtin.apt:
      update_cache: yes
    register: upgrade_result 

  - name: Upgrade all packages
    ansible.builtin.apt: 
      upgrade: dist 
      autoremove: yes
      autoclean: yes
    register: upgrade_result 

  - name: Install additional packages
    ansible.builtin.apt:
      name: "{{ additional_packages }}" 
      state: present
      update_cache: yes

  - name: Reboot the server if changes or requested
    ansible.builtin.reboot:
      reboot_timeout: 900
      post_reboot_delay: 10
      test_command: whoami
    when: upgrade_result.changed or hostname_result.changed or ( (force_reboot is defined) and ( force_reboot | bool ) )
    register: reboot_result

  - name: Wait for server to come back  
    ansible.builtin.wait_for_connection: 
      timeout: 300
    when: reboot_result.changed

  - name: Install additional packages
    ansible.builtin.apt:
      name: "{{ k8s_dependencies }}" 
      state: present
      update_cache: yes
```

In here, I would change the hostname (of the VM - as conigured within the template) to real name and would update the system and install some additional packages (like net-tools, curl, wget, git, etc). The list of packages is defined in group_vars/all.yaml file:
```yaml ( group_vars/all.yaml )
additional_packages:
  - socat
  - net-tools    
  - hping3
  - wget
  - curl
  - git
k8s_dependencies:
  - apt-transport-https
  - ca-certificates
  - curl
  - gnupg
  - lsb-release

``` 

Also I need to introduce an inventory file for ansible. 

```ini ( inventory )
[k8s-cp]
s1 ansible_host=10.199.0.11
s2 ansible_host=10.199.0.12
s3 ansible_host=10.199.0.13

[k8s-workers]
s4 ansible_host=10.199.0.14
s5 ansible_host=10.199.0.15
s6 ansible_host=10.199.0.16
s7 ansible_host=10.199.0.17
s8 ansible_host=10.199.0.18

[k8s-all:children]
k8s-cp
k8s-workers

[all:vars]
ansbible_user=lab
```

One more comment - for the reboot, I am using fairly complex 'when' statement - the idea is to reboot the server only if there was a change (hostname changed or system updated) or if I explicitly set the variable `force_reboot`. The idea here is to always reboot the servers after an update but also this gives me an opportunity to reboot 'easily' any / all servers using ansible:
```bash
ansible-playbook -i inventory 02_initial_setup_of_VMs.yaml --extra-vars "force_reboot=true" 
```
```bash
ansible-playbook -i inventory 02_initial_setup_of_VMs.yaml -e "force_reboot=true" --host s1
```
