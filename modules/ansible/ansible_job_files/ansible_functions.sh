#!/bin/bash
#
# Ansible Function Library (OCI)
#
# Common functions used across ansible job scripts

# Function to check if a command exists
command_exists() {
  command -v "$1" &> /dev/null
}

# Function to log with timestamp
log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

# Function to log error with timestamp
log_error() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2
}

# Function to wait for a host to be reachable
wait_for_host() {
  local host="$1"
  local port="${2:-22}"
  local timeout="${3:-300}"

  log "Waiting for $host:$port to be reachable (timeout: ${timeout}s)..."

  local elapsed=0
  while ! nc -z -w1 "$host" "$port" &>/dev/null; do
    sleep 5
    elapsed=$((elapsed + 5))
    if [ $elapsed -ge $timeout ]; then
      log_error "Host $host:$port did not become reachable after ${timeout}s"
      return 1
    fi
  done

  log "Host $host:$port is reachable"
  return 0
}

# Function to check if ansible is installed
check_ansible() {
  if ! command_exists ansible-playbook; then
    log_error "ansible-playbook command not found. Please install Ansible."
    return 1
  fi
  return 0
}

# Ensure ansible is installed
check_ansible || exit 1

# Export functions for use in other scripts
export -f command_exists
export -f log
export -f log_error
export -f wait_for_host
export -f check_ansible
