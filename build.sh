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
curl -s https://get.docker.com/ | sh

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

# Use the standing host keys for sandbox.plushu.org
cat >/etc/ssh/ssh_host_dsa_key <<"_EOF_"
-----BEGIN DSA PRIVATE KEY-----
MIIBuwIBAAKBgQDQwAyHCcs5qjM1ja8WagcSHWvbTlbHiMITIAHZQtfSP21C/XJ8
b7oT/Pka0+/pjHLo+yB7q3ouaRF2VTAijRoscMPlv5jQiZJTSRKre9XUPEJdbDgS
XdJTOx3Fb89QZ6So4K0Tl5v7Oo3kwQTpO5XFZY7U0y5qxLMuaMze9wLroQIVAIwp
GARYKF0ili61qZjWMLoxrqmHAoGAEhxR+giUyF8SFcIPu+ePL3s4uO2lR5306zUF
uWinKFiftqCmVsfSmN5TXZ6erYg/6ptOZbqzM8gWemSNrynArjai8peIHnnMk1uK
xmlKI0FyrjKKLUrc7CKU23exuuPSk02bVXAmz73ppZRXs1iMzbX3odV/ZwcegGO7
gd41Q4QCgYEAp954MGNulOl929lKgMthj4lLXNoczdrkTeaQE0sDcVXkc8DkV/cd
Ao+8Sl5AZ9AZmErNNuV1VGuu5ZOQF1rGWuPGcSOnCXfZzVRnuxC8DMXfEkC86nIe
fpRlGIKgSKeR4izmT0JAKLNsOLOYoGhsmy5rqVnF5QZBJUER7/C7cQwCFHyzx08f
l0aQI+7X45oMBrwxGKTe
-----END DSA PRIVATE KEY-----
_EOF_
cat >/etc/ssh/ssh_host_ecdsa_key <<"_EOF_"
-----BEGIN EC PRIVATE KEY-----
MHcCAQEEIOwY7HlGmUjA+B9m15qWRHeGYaV8I1G2yBOitPJaBrxaoAoGCCqGSM49
AwEHoUQDQgAEBSYPqxj5UHRh3l0KyEOWYihCmxUWhjFgp3V5ZJs8NXH96NK1Drhg
F1zdIgb9HSPxnJV2dorJLDXiS+71BbQmJg==
-----END EC PRIVATE KEY-----
_EOF_
cat >/etc/ssh/ssh_host_rsa_key <<"_EOF_"
-----BEGIN RSA PRIVATE KEY-----
MIIEowIBAAKCAQEAtyhtL/XlEOfVaByurCwC6yGiXYjMieUvNW0VO8auPL1NjJb1
tx0yDfVNcPb/Pr/Vm4gN2+7PEzhCvXHCagiWN5AFMU+dzgMbmP1HErnl73f7BXxk
BtmwHfdcQTFY/6L16jF7R1ySN20H+K9XA9ccEjQmnmudICklSFLxl+Ue0ZOb0bXW
zyHqyt/WtTFpVqPUN/T8Eokm9me5v+NQxaCa1XobQ7qPDzsfH37kRt00PVggsjlc
Vtq2wMf3QhldR7822uKUpY3Ihv3xfVO+zdF7pVMcdnAtU1hQpfARMUJ7/iaWan8x
4CrFZWgKLnzSxDewQ5l2jOBws1l6T8vHz5bZvQIDAQABAoIBAC1NcIRWW8wsq5pO
zd2EHUyvSwu7lGvfJigezQu1/s7DO/U0OZ6LOCA/tmHklgmdRWZs5pCppspoNgnJ
o366lP01QDOML8oO9rqGmxfEp1zt3kbjF5KiMW+YCVeOrya71fuRNZ7XBMt0ym32
YJ1wjV7rS0oP8BNOWgxjh6I8Z70KS7YF3Nqm/ZirB/cVlZsjlFi02YviZBwshJYS
ETepWLzYGRpMiv2tmIBwMOzWUzbGNnW7X92aYkaCJj/N/H2P6JMJ2uS4TLrOVrj8
ZGwjeM1yeDjTe37X0BUG61bmWZ5xtXbtvCDYheI9WPWVPi1Rm5rpaI9+MYnAFDzD
nWvAsnkCgYEA89regxzDTUx5EyE6NkAUkIcoltpd2i1bk4cKrhy6dUyWmhthbLbQ
PDA2YmPkl8cWGx7VFT6LAlYWu0z5yU9do50MwHgQws18d7q2vt513dE73l0WrfP0
Rd+NNbKTBXhFCLe9QAsm7fHkbUb+0bUoBIIdqNXQh2jd4hFJXgUBgWsCgYEAwEes
zJDsTbbdxJY/NBZiCsz8Pktn2W0nzl+niAGE01itFWnUlM66MdWoEDnXywh52GjR
MM/Rnhp1ZkBLANo19Blg/s8XnDY4RJzRydIchokWPLBVKk7RwVtsCwCR0+CCpATk
c2sBBNvqh+q18hwsLZBSFmkY7a6lchNdtUJKU3cCgYEAxR33ICTv+lwGwt/pHlFO
TkXzGX4Kv4JKtEZE69ltH8R5OLlJV4eva/fM/luhPM9Bn0qdFD8qPwk39s+SWpg9
KTSaSjrD0bQpGN9lOYS54kRwEJ9O5e59Vr4Od4mSLqm5pAJiiJJ7NXyDGZJ6CSpW
3s4PC5tKpSqvsT4oAEgrn2ECgYAg/etjalZxezgQHCuaF2EZM1Twp2WZRAZ5faY0
SvZsgSGps+/63IHMPTnKFvK07q5heJK0SmRQOX/9XHjCG674REaFUild71u2QiYo
9/lXCDydizABw2ZwQ+yE8sMS1Mn1tLUyLKEPIWDbk2VGtpjJ9KJxH/VcCwRuT25b
xJUWPwKBgHp/coPRrwwdnfsRmyAlRC7QHLIQoSqptg0NUxKNXRxwYxkKfh8empPN
injZstq20vnzOYKyj58sGD24Y+SDfjrqw17EoU0ousBe8pMuwnINCqzbdANh/SUU
O1QaBur4BSXJVIvOVT40vrkEa5ra4ZT84NVKj3K249HtHsZeI6ed
-----END RSA PRIVATE KEY-----
_EOF_
for key in /etc/ssh/ssh_host_*_key; do ssh-keygen -yf "$key" >"$key.pub"; done

# Add the public key used by reset-sandbox.plushu.org to warn the server
cat >>/root/.ssh/authorized_keys <<<"ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDE3oFZVm3Jcpp2DFX3DE/7GAvzbhywejEAZ7yGMs+LqJqhnE/aHLRw0JlcySjKv+iKPBuVCUfJdMcvUAq15OFEKD2dHEY9j0jG0KsD+2poQVbO6w0MkDdxHx2R49M3LydE6PYKbT6cASkaSnYcqpVYDlRdTPh1y7+QmDAqf6wmw73ln/XWVwLYEINzYdWyiQAH1tWGbRdH5OHHJUguWslyYYNx7xQmvO5ue4sQn9r/cFjw24wLp1knzmj9DCO0I+2iIv4I36BIyS8L2BZHzBLYrT9JhtjHOPhgzSjFu4choHEmCLoqwrxQWQ3QLBZTS9F7aNaNAdC0H6oB8830aB37 root@sandbox.plushu.org"

# Install Plushu
git clone https://github.com/plushu/plushu /home/plushu
/home/plushu/install.sh

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
