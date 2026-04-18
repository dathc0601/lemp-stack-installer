location {{PMA_PATH}} {
    alias {{PMA_DIR}};
    index index.php;

    # HTTP basic-auth gate — triggers fail2ban [nginx-http-auth] jail on brute force.
    # User file is managed by `lemp-manage appadmin-{add,password,remove} pma <user>`.
    auth_basic           "phpMyAdmin — admin access";
    auth_basic_user_file {{PMA_HTPASSWD_FILE}};

    # Rate limit logins
    limit_req zone=admin burst=20 nodelay;

    location ~ ^{{PMA_PATH}}/(.+\.php)$ {
        alias {{PMA_DIR}}/$1;
        include fastcgi_params;
        fastcgi_pass unix:/run/php/php{{PHP_VERSION}}-fpm.sock;
        fastcgi_param SCRIPT_FILENAME $request_filename;
        fastcgi_read_timeout {{PHP_MAX_EXEC_TIME}};
    }

    location ~* ^{{PMA_PATH}}/(.+\.(jpg|jpeg|gif|css|png|js|ico|html|xml|txt|woff|woff2|ttf|svg))$ {
        alias {{PMA_DIR}}/$1;
        expires 30d;
        access_log off;
    }
}
