# Default catch-all — silently drop requests for unknown hosts / direct IP access.
# Admin tools are accessible ONLY via your configured domains.
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;
    return 444;
}
