# Template: Default catch-all vhost (returns 444 for unknown hosts)
# No placeholders — static content

server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;
    return 444;
}
