-- Add apns_environment column to device_tokens.
--
-- Each APNs token is environment-specific: tokens from debug/Xcode builds are
-- sandbox tokens (must go to api.sandbox.push.apple.com) and tokens from
-- TestFlight/App Store builds are production tokens (api.push.apple.com).
-- Sending a sandbox token to the production endpoint returns 400 BadDeviceToken
-- and the push is silently dropped — this was the root cause of widgets not
-- updating when the device was disconnected from Xcode USB.
--
-- Default is 'sandbox' for backward compatibility with existing rows that were
-- saved before this column existed (all existing rows are from debug builds).

ALTER TABLE device_tokens
    ADD COLUMN IF NOT EXISTS apns_environment TEXT NOT NULL DEFAULT 'sandbox';
