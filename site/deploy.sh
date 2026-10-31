#!/usr/bin/env bash
# Deploys site/public to S3 and invalidates CloudFront.
# Reads DOMAIN_NAME and CF_DISTRIBUTION_ID from site/.env.deploy (gitignored).
set -euo pipefail
cd "$(dirname "$0")"
[ -f .env.deploy ] && set -a && . ./.env.deploy && set +a
: "${DOMAIN_NAME:?set DOMAIN_NAME in site/.env.deploy}"

echo "Syncing html and text (no-cache)..."
aws s3 sync ./public/ "s3://$DOMAIN_NAME/" --delete \
  --cache-control "public, max-age=0, must-revalidate"

echo "Setting 30-day cache on images..."
aws s3 sync ./public/ "s3://$DOMAIN_NAME/" --exclude "*" \
  --include "*.png" --include "*.jpg" --include "*.svg" --include "*.ico" --include "*.webp" \
  --cache-control "public, max-age=2592000"

if [ -n "${CF_DISTRIBUTION_ID:-}" ]; then
  echo "Invalidating CloudFront..."
  aws cloudfront create-invalidation --distribution-id "$CF_DISTRIBUTION_ID" --paths "/*" >/dev/null
else
  echo "CF_DISTRIBUTION_ID not set; skipping invalidation (terraform output cloudfront_distribution_main)."
fi

if [ -n "${INDEXNOW_KEY:-}" ]; then
  STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X POST "https://api.indexnow.org/indexnow" \
    -H "Content-Type: application/json; charset=utf-8" \
    -d "{\"host\":\"$DOMAIN_NAME\",\"key\":\"$INDEXNOW_KEY\",\"keyLocation\":\"https://$DOMAIN_NAME/$INDEXNOW_KEY.txt\",\"urlList\":[\"https://$DOMAIN_NAME/\"]}" || echo "curl-failed")
  echo "IndexNow: HTTP $STATUS"
fi

git -C .. tag -f "deploy-$(date -u +%Y-%m-%d-%H%M)" >/dev/null 2>&1 || true
echo "Deployed https://$DOMAIN_NAME"
