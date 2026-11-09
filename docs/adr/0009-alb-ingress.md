# ADR-0009: AWS Load Balancer Controller (ALB) for ingress

- **Status:** Accepted
- **Deciders:** Platform owner

## Context
Getting internet traffic to pods with TLS, WAF and health checks.

## Decision
Ingress objects with `ingressClassName: alb` create an Application Load Balancer. `target-type: ip` sends traffic straight to pod IPs; `group.name` lets the frontend (`/`) and backend (`/api`) share one ALB per environment; TLS terminates with an ACM certificate.

## Consequences
Native AWS integration (ACM, WAF, Shield, access logs), no proxy pods to run and scale, direct-to-pod routing. Costs: AWS lock-in, no in-cluster L7 features (rate limiting, rewrites) of NGINX, and DNS records are manual until external-dns is added. NetworkPolicies must allow the VPC CIDR because the ALB's ENIs are the source.

## Alternatives considered
ingress-nginx behind an NLB (portable, rich features, but more to operate); Gateway API (the future direction; ALB support is maturing).
