package test

import (
	"os"
	"testing"

	"github.com/stretchr/testify/require"
)

// getRequiredEnvVar reads a required environment variable and fails the test if it's not set.
// This helper is now centralized here to be used by all tests in the package.
func getRequiredEnvVar(t *testing.T, key string) string {
	value, found := os.LookupEnv(key)
	require.True(t, found, "Environment variable '%s' must be set for this test", key)
	return value
}

// OCI-specific environment variables that are commonly needed:
// OCI_REGION - The OCI region (e.g., "us-ashburn-1")
// OCI_COMPARTMENT_ID - The OCID of the compartment
// OCI_TENANCY_OCID - The OCID of the tenancy (optional, can be in config file)
// OCI_USER_OCID - The OCID of the user (optional, can be in config file)  
// OCI_FINGERPRINT - The fingerprint of the API key (optional, can be in config file)
// OCI_KEY_FILE - Path to the private key file (optional, can be in config file)
// OCI_CONFIG_FILE_PROFILE - The profile name in the config file (optional, defaults to "DEFAULT")