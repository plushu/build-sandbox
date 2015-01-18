#!/usr/bin/env bash

if [[ $EUID != 0 ]]; then
  echo "You need to be root to set up the sandbox" >&2
  exit 1
fi

# Stop bash from remembering root's commands
rm -rf /root/.bash_history; ln -s /dev/null/ /root/.bash_history
printf '\nunset HISTFILE\n' >>/root/.bashrc

# Don't track logins
rm -rf /var/log/lastlog /var/log/wtmp /var/log/btmp

# Set the time zone local to the datacenter
timedatectl set-timezone America/Los_Angeles

# Add the `timeleft` script
cat >/usr/local/bin/timeleft <<"EOF"
#!/usr/bin/env bash

if [[ `date +%H` -ge 12 ]]; then
  noon=`date -d '12:00 tomorrow' +%s`
else
  noon=`date -d '12:00' +%s`
fi

timespan=$(($noon - `date +%s`))

hours=$((timespan/3600))
minutes=$((timespan/60%60))
seconds=$((timespan%60))

if [[ "$hours" == 1 ]]; then echo -n "1 hour"
  elif [[ "$hours" != 0 ]]; then echo -n "$hours hours"; fi
if [[ "$hours" != 0 && "$minutes" != 0 ]]; then echo -n ' and '; fi
if [[ "$minutes" == 1 ]]; then echo -n "1 minute"
  elif [[ "$minutes" != 0 ]]; then echo -n "$minutes minutes"; fi
if [[ "$hours" == 0 ]]; then
  if [[ "$minutes" != 0 ]]; then echo -n ' and '; fi
  if [[ "$seconds" == 1 ]]; then echo -n "1 second"
    else echo -n "$seconds seconds"; fi
fi
echo
EOF
chmod +x /usr/local/bin/timeleft

# Add the `reset-sandbox` script
cat >/usr/local/bin/reset-sandbox <<"EOF"
#!/usr/bin/env bash

url=https://reset-sandbox.plushu.org

curl -isSXPOST "$url/" |
  sed -n '/^Location:[[:space:]]/{s#^[^:]*:[[:space:]]*#'"$url"'#;p;q}'
EOF
chmod +x /usr/local/bin/reset-sandbox

# Remove all of Ubuntu's initial motd stuff
rm /etc/update-motd.d/*

# Fix https://github.com/plushu/build-sandbox/issues/3
sed -i 's#^\(session    optional     pam_motd\.so  motd=/run/motd\.dynamic\) noupdate$#\1#' /etc/pam.d/sshd

# Create our own motd stuff
cat >/etc/update-motd.d/00-header <<"EOF"
#!/usr/bin/env bash

[[ -r /etc/lsb-release ]] && . /etc/lsb-release

if [[ -z "$DISTRIB_DESCRIPTION" ]] && [[ -x /usr/bin/lsb_release ]]; then
  # Fall back to using the very slow lsb_release utility
  DISTRIB_DESCRIPTION=$(lsb_release -s -d)
fi

echo "Welcome to sandbox.plushu.org, running on $DISTRIB_DESCRIPTION"

EOF

cat >/etc/update-motd.d/50-plushu-sandbox <<"EOF"
#!/usr/bin/env bash

if [[ `date +%H` -ge 12 ]]; then
  noon=`date -d '12:00 tomorrow' +%s`
else
  noon=`date -d '12:00' +%s`
fi

servertz=`date -d "1970-01-01 UTC $noon seconds" +%Z`
utcnoon=`date -d "1970-01-01 UTC $noon seconds" -u "+%H:%M %Z"`

echo
echo "  This server will be reset in `timeleft`, at $utcnoon"
echo "  (noon in $servertz, the server's local time zone.)"
echo
echo "  You can check the time remaining at any time with \`timeleft\`,"
echo "  or via \`ssh plushu@sandbox.plushu.org timeleft\`."
echo
echo "  The server may also be reset at any time via:"
echo "    https://reset-sandbox.plushu.org"
echo
echo "  This server can be controlled by anybody who enters a public key at:"
echo "    http://enter.sandbox.plushu.org"
echo
echo "  Keeping these things in mind, be careful not to keep or do anything on"
echo "  this server that you wouldn't be comfortable losing at a second's"
echo "  notice, or anything that you wouldn't be comfortable exposing to"
echo "  random strangers on the Internet. Specifically:"
echo
printf "  \033[1;31m!! DO NOT UPLOAD A PRIVATE KEY OR ENTER A PASSWORD ON THIS SERVER !!\033[0m\n"
echo
echo "  Happy hacking!"
echo
EOF

chmod +x /etc/update-motd.d/*

# Get Docker
curl -s https://get.docker.io/ubuntu/ | sh

# Update apt-get lists
apt-get update

# Install any pending updates
apt-get upgrade

# Install other dependencies:
# - git:
#   - required to install plugins via Git
#   - required for app deployment over Git
# - inotify-tools:
#   - optional
#   - lets Docker-dependent Upstart units connect to docker socket as soon it
#     becomes available
# - mosh:
#   - for using mosh to connect (to do root stuff) instead of SSH
apt-get install -y git inotify-tools mosh

# Install Plushu
git clone https://github.com/plushu/plushu /home/plushu
/home/plushu/install.sh

# Add the public key used by reset-sandbox.plushu.org to warn the server
cat >>/root/.ssh/authorized_keys <<<"ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDE3oFZVm3Jcpp2DFX3DE/7GAvzbhywejEAZ7yGMs+LqJqhnE/aHLRw0JlcySjKv+iKPBuVCUfJdMcvUAq15OFEKD2dHEY9j0jG0KsD+2poQVbO6w0MkDdxHx2R49M3LydE6PYKbT6cASkaSnYcqpVYDlRdTPh1y7+QmDAqf6wmw73ln/XWVwLYEINzYdWyiQAH1tWGbRdH5OHHJUguWslyYYNx7xQmvO5ue4sQn9r/cFjw24wLp1knzmj9DCO0I+2iIv4I36BIyS8L2BZHzBLYrT9JhtjHOPhgzSjFu4choHEmCLoqwrxQWQ3QLBZTS9F7aNaNAdC0H6oB8830aB37 root@sandbox.plushu.org"

# Give everybody with root access plushu access
cat /root/.ssh/authorized_keys >/home/plushu/.ssh/authorized_keys

# Add plugin for opts to enable tracing
plushu plugins:install trace

# Add command whitelisting, whitelist some commands for plushu
plushu plugins:install command-whitelist
plushu command-whitelist timeleft reset-sandbox docker

# Install Plusku
plushu plugins:install plusku

# Install plugin for setting up Docker options
plushu plugins:install app-docker-opts

# This would be where we would do:
# plushu apps:clone plushu/enter-sandbox enter
# But we haven't added apps:clone yet, so instead we do:
plushu apps:create enter

# Set Docker options to make authorized_keys available to enter-sandbox
plushu app-docker-opts:add enter '-v /root/.ssh:/root-ssh'
plushu app-docker-opts:add enter '-v /home/plushu/.ssh:/plushu-ssh'

# At this point, we run:

# plushu plugins:disable deploy-app-local-container

# And then we push enter-sandbox to finish the build...

# after re-enabling deploy-app-local-container with:

# plushu plugins:enable deploy-app-local-container
