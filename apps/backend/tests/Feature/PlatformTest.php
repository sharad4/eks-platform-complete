<?php

namespace Tests\Feature;

use Tests\TestCase;

class PlatformTest extends TestCase
{
    public function test_liveness_does_not_depend_on_anything(): void
    {
        $this->getJson('/healthz')->assertOk()->assertJson(['status' => 'ok']);
    }

    public function test_ping_returns_pong(): void
    {
        $this->getJson('/api/ping')->assertOk()->assertJson(['pong' => true]);
    }

    public function test_metrics_expose_request_counters(): void
    {
        $this->getJson('/api/ping')->assertOk();

        $this->get('/metrics')
            ->assertOk()
            ->assertSee('http_requests_total', false)
            ->assertSee('http_request_duration_seconds_bucket', false);
    }
}
