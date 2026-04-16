server {
    listen 80;
    listen [::]:80;
    server_name {{DOMAIN}} www.{{DOMAIN}};

    root {{SITE_ROOT}};
    index index.php index.html index.htm;

    access_log /var/log/nginx/{{DOMAIN}}.access.log;
    error_log  /var/log/nginx/{{DOMAIN}}.error.log;

    client_max_body_size {{PHP_UPLOAD_MAX}};

    include {{NGINX_SNIPPETS_DIR}}/security-headers.conf;

    # WordPress-style pretty permalinks
    location / {
        try_files $uri $uri/ /index.php?$args;
    }

    # Rate-limit login endpoints
    location = /wp-login.php {
        limit_req zone=login burst=2 nodelay;
        include fastcgi_params;
        fastcgi_pass unix:/run/php/php{{PHP_VERSION}}-fpm.sock;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        fastcgi_read_timeout {{PHP_MAX_EXEC_TIME}};
    }

    location ~ \.php$ {
        include fastcgi_params;
        fastcgi_pass unix:/run/php/php{{PHP_VERSION}}-fpm.sock;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        fastcgi_index index.php;
        fastcgi_intercept_errors on;
        fastcgi_buffer_size 128k;
        fastcgi_buffers 4 256k;
        fastcgi_busy_buffers_size 256k;
        fastcgi_read_timeout {{PHP_MAX_EXEC_TIME}};
    }

    # Block hidden files
    location ~ /\. {
        deny all;
        access_log off;
        log_not_found off;
    }

    # Block sensitive files
    location ~* /(?:wp-config\.php|readme\.html|license\.txt|\.env|composer\.(json|lock))$ {
        deny all;
    }

    # Block xmlrpc — frequent attack vector
    location = /xmlrpc.php {
        deny all;
    }

    # Static asset caching
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|webp|woff|woff2|ttf|eot)$ {
        expires 30d;
        add_header Cache-Control "public, immutable";
        access_log off;
    }

    # Gzip
    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types text/plain text/css application/json application/javascript
               text/xml application/xml application/xml+rss text/javascript
               image/svg+xml;

    # Admin tools (random paths for obscurity)
    include {{NGINX_SNIPPETS_DIR}}/phpmyadmin.conf;
    include {{NGINX_SNIPPETS_DIR}}/filebrowser.conf;
}
