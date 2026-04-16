#!/bin/bash
###############################################################################
#  modules/45-redis.sh — Redis server
#
#  Installs redis-server package and enables the service.
#  The php-redis extension is installed by the PHP module.
###############################################################################

module_redis_describe() {
    echo "Redis server"
}

module_redis_check() {
    return 1
}

module_redis_install() {
    # TODO: migrate from server-setup.sh install_redis()
    return 0
}
