defmodule LocalizeCacheProbe.CacheTest do
  use ExUnit.Case, async: true

  alias LocalizeCacheProbe.Cache

  doctest LocalizeCacheProbe.Cache

  describe "vendor/1" do
    test "recognises each vendor from a header it adds" do
      assert Cache.vendor([{"cf-ray", "8f1c-SYD"}]) == :cloudflare
      assert Cache.vendor([{"server", "cloudflare"}]) == :cloudflare
      assert Cache.vendor([{"x-amz-cf-pop", "SYD62-P1"}]) == :cloudfront
      assert Cache.vendor([{"via", "1.1 abc.cloudfront.net (CloudFront)"}]) == :cloudfront
      assert Cache.vendor([{"x-served-by", "cache-syd10137-SYD"}]) == :fastly
      assert Cache.vendor([{"server", "AkamaiGHost"}]) == :akamai
      assert Cache.vendor([{"x-azure-ref", "20261117T000000Z-abc"}]) == :front_door
      assert Cache.vendor([{"via", "1.1 google"}]) == :google
      assert Cache.vendor([{"x-varnish", "32770"}]) == :varnish
      assert Cache.vendor([{"server", "nginx/1.27.2"}]) == :nginx
    end

    test "takes Fastly ahead of the Varnish it is built on" do
      headers = [{"via", "1.1 varnish"}, {"x-served-by", "cache-syd10137-SYD"}]

      assert Cache.vendor(headers) == :fastly
    end

    test "matches header names without regard to case" do
      assert Cache.vendor([{"CF-Cache-Status", "HIT"}]) == :cloudflare
    end

    test "is :unknown for no headers, unrelated headers and malformed entries" do
      assert Cache.vendor([]) == :unknown
      assert Cache.vendor([{"content-type", "text/html"}]) == :unknown
      assert Cache.vendor([nil, {:server, "nginx"}, {"server", nil}, "server"]) == :unknown
    end
  end

  describe "status/1" do
    test "reads a vendor's status header" do
      assert Cache.status([{"cf-cache-status", "HIT"}]) == :hit
      assert Cache.status([{"cf-cache-status", "MISS"}]) == :miss
      assert Cache.status([{"cf-cache-status", "EXPIRED"}]) == :miss
      assert Cache.status([{"cf-cache-status", "DYNAMIC"}]) == :uncacheable
      assert Cache.status([{"cf-cache-status", "BYPASS"}]) == :uncacheable
      assert Cache.status([{"x-cache", "Hit from cloudfront"}]) == :hit
      assert Cache.status([{"x-cache", "RefreshHit from cloudfront"}]) == :hit
      assert Cache.status([{"x-cache", "TCP_REMOTE_HIT"}]) == :hit
      assert Cache.status([{"x-cache", "TCP_MISS"}]) == :miss
      assert Cache.status([{"x-cache", "PRIVATE_NOSTORE"}]) == :uncacheable
      assert Cache.status([{"x-cache", "CONFIG_NOCACHE"}]) == :uncacheable
      assert Cache.status([{"x-cache-status", "HIT"}]) == :hit
    end

    test "takes the last of several x-cache values" do
      assert Cache.status([{"x-cache", "MISS, HIT"}]) == :hit
      assert Cache.status([{"x-cache", "HIT, MISS"}]) == :miss
    end

    test "reads a Varnish hit from two request ids" do
      assert Cache.status([{"x-varnish", "32770 3"}]) == :hit
      assert Cache.status([{"x-varnish", "32770"}]) == :miss
    end

    test "falls back to the age header" do
      assert Cache.status([{"age", "42"}]) == :hit
      assert Cache.status([{"age", " 7 "}]) == :hit
      assert Cache.status([{"age", "0"}]) == :hit
      assert Cache.status([{"age", "-1"}]) == :unknown
      assert Cache.status([{"age", "0"}, {"x-varnish", "32770"}]) == :miss
      assert Cache.status([{"age", "soon"}]) == :unknown
      assert Cache.status([{"age", ""}]) == :unknown
    end

    test "prefers a vendor header to age" do
      assert Cache.status([{"age", "42"}, {"cf-cache-status", "MISS"}]) == :miss
    end

    test "is :unknown for no headers and for values it cannot read" do
      assert Cache.status([]) == :unknown
      assert Cache.status([{"x-cache", "Error from cloudfront"}]) == :unknown
      assert Cache.status([{"x-cache", ""}, {"x-varnish", ""}]) == :unknown
    end
  end

  describe "vary_note/1" do
    test "has a summary and a source for each documented vendor" do
      for vendor <- [:akamai, :cloudflare, :cloudfront, :front_door, :google] do
        assert {:ok, %{summary: summary, source: "https://" <> _rest}} = Cache.vary_note(vendor)
        assert String.ends_with?(summary, ".")
      end
    end

    test "is :error where no documentation has been read" do
      for vendor <- [:fastly, :varnish, :nginx, :unknown, :"", nil] do
        assert Cache.vary_note(vendor) == :error
      end
    end
  end
end
