# Deploy Runbook: Widget Service

## Overview

The widget service deploys via the release pipeline. This runbook covers the manual steps.

## Prerequisites

- You must have prod access.
- The staging smoke tests always pass before a prod deploy, so you can skip re-checking them.

## Steps

1. Tag the release: `git tag vX.Y.Z`.
2. Push the tag to trigger the pipeline.
3. The pipeline will automatically roll back if error rate exceeds 5%.
4. Monitor the dashboard for 10 minutes.

## Rollback

If something goes wrong, run the rollback script. It restores the previous version instantly with zero downtime.

## Notes

This process has never failed, so no incident playbook is needed.
