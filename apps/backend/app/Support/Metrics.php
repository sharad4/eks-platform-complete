<?php

namespace App\Support;

use Prometheus\CollectorRegistry;
use Prometheus\Storage\APC;
use Prometheus\Storage\APCng;
use Prometheus\Storage\InMemory;

/**
 * One metrics registry per pod.
 *
 * APCu is shared memory across all php-fpm workers of a SINGLE pod, which is
 * exactly the right scope: Prometheus scrapes every pod separately and sums
 * across them. (A Redis-backed registry would mix pods together and break
 * per-pod rate() maths.) Falls back to in-memory for CLI/tests, where APCu is off.
 */
final class Metrics
{
    private static ?CollectorRegistry $registry = null;

    public static function registry(): CollectorRegistry
    {
        if (self::$registry === null) {
            if (function_exists('apcu_enabled') && apcu_enabled()) {
                $adapter = class_exists(APCng::class) ? new APCng() : new APC();
            } else {
                $adapter = new InMemory();
            }

            self::$registry = new CollectorRegistry($adapter, false);
        }

        return self::$registry;
    }
}
