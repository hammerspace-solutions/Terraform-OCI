package test

import (
	"context"
	"fmt"
	"path/filepath"
	"regexp"
	"strconv"
	"testing"
	"time"

	"github.com/gruntwork-io/terratest/modules/random"
	"github.com/gruntwork-io/terratest/modules/retry"
	"github.com/gruntwork-io/terratest/modules/ssh"
	"github.com/gruntwork-io/terratest/modules/terraform"
	test_structure "github.com/gruntwork-io/terratest/modules/test-structure"
	"github.com/oracle/oci-go-sdk/v65/common"
	"github.com/oracle/oci-go-sdk/v65/core"
	"github.com/stretchr/testify/require"
)

// NOTE: This test depends on the getRequiredEnvVar helper function located in test_helpers.go

func TestStorageModuleWithRAID(t *testing.T) {
	t.Parallel()

	// --- Test Setup: Read shared variables & generate SSH key ---
	region := getRequiredEnvVar(t, "OCI_REGION")
	compartmentId := getRequiredEnvVar(t, "OCI_COMPARTMENT_ID")
	vcnId := getRequiredEnvVar(t, "VCN_ID")
	subnetId := getRequiredEnvVar(t, "SUBNET_ID")
	storageImageId := getRequiredEnvVar(t, "STORAGE_IMAGE_ID")
	availabilityDomain := getRequiredEnvVar(t, "AVAILABILITY_DOMAIN")

	sshKeyPair := ssh.GenerateRSAKeyPair(t, 2048)

	projectRoot, err := filepath.Abs("../")
	require.NoError(t, err, "Failed to get project root path")
	userDataScriptPath := filepath.Join(projectRoot, "templates", "storage_server_ubuntu.sh")

	testCases := map[string]struct {
		raidLevel    string
		diskCount    int
		instanceType string
	}{
		"RAID-0": {
			raidLevel:    "raid-0",
			diskCount:    2,
			instanceType: "VM.Standard.E4.Flex",
		},
		"RAID-5": {
			raidLevel:    "raid-5",
			diskCount:    3,
			instanceType: "VM.Standard.E4.Flex",
		},
		"RAID-6": {
			raidLevel:    "raid-6",
			diskCount:    4,
			instanceType: "VM.Standard.E4.Flex",
		},
	}

	for testName, tc := range testCases {
		tc := tc
		t.Run(testName, func(t *testing.T) {
			t.Parallel()

			tempTestFolder := test_structure.CopyTerraformFolderToTemp(t, "../modules/storage_servers", "examples")
			projectName := fmt.Sprintf("terratest-storage-%s-%s", tc.raidLevel, random.UniqueId())

			terraformOptions := &terraform.Options{
				TerraformDir:    tempTestFolder,
				TerraformBinary: "terraform",
				Vars: map[string]interface{}{
					"project_name":           projectName,
					"region":                 region,
					"compartment_id":         compartmentId,
					"vcn_id":                 vcnId,
					"subnet_id":              subnetId,
					"storage_image_id":       storageImageId,
					"availability_domain":    availabilityDomain,
					"ssh_public_key":         sshKeyPair.PublicKey,
					"storage_instance_count": 1,
					"storage_instance_type":  tc.instanceType,
					"storage_block_count":    tc.diskCount,
					"storage_raid_level":     tc.raidLevel,
					"storage_user_data":      userDataScriptPath,
					"allow_test_ingress":     true, // Tell the module to open ports for this test
				},
			}

			defer terraform.Destroy(t, terraformOptions)
			terraform.InitAndApply(t, terraformOptions)

			// --- Validation ---
			publicIp := terraform.Output(t, terraformOptions, "public_ip")
			require.NotEmpty(t, publicIp, "Instance public IP should not be empty")

			host := ssh.Host{
				Hostname:    publicIp,
				SshKeyPair:  sshKeyPair,
				SshUserName: "ubuntu",
			}

			// Step 1: Patiently wait for the instance to reboot and SSH to become available.
			maxRetries := 40
			sleepBetweenRetries := 15 * time.Second
			description := fmt.Sprintf("Wait for SSH to be ready on instance %s", publicIp)
			
			retry.DoWithRetry(t, description, maxRetries, sleepBetweenRetries, func() (string, error) {
				// The correct function is CheckSshCommandE, which returns (string, error).
				// We discard the output string with `_` because we only care if the command succeeds.
				_, err := ssh.CheckSshCommandE(t, host, `echo "Instance is ready"`)
				if err != nil {
					return "", err // If there's an error (e.g., connection refused), the retry continues.
				}
				return "SSH connection successful.", nil // If the command succeeds, we stop retrying.
			})

			// Step 2: Now that the instance is stable, run the real validation command.
			mdstatOutput, err := ssh.CheckSshCommandE(t, host, "cat /proc/mdstat")
			require.NoError(t, err, "Failed to run 'cat /proc/mdstat' via SSH")

			// --- Deep Validation of RAID Array ---
			require.Contains(t, mdstatOutput, "md0 : active", "RAID device md0 is not active")
			require.Contains(t, mdstatOutput, tc.raidLevel, "Incorrect RAID level found in mdstat output")

			re := regexp.MustCompile(`\[(\d+)/\d+\]`)
			matches := re.FindStringSubmatch(mdstatOutput)
			require.Len(t, matches, 2, "Could not parse number of disks from mdstat output")

			activeDisksStr := matches[1]
			activeDisks, err := strconv.Atoi(activeDisksStr)
			require.NoError(t, err, "Could not convert active disk count to integer")

			require.Equal(t, tc.diskCount, activeDisks, "Incorrect number of active disks in the RAID array")
			t.Logf("Successfully validated RAID level %s with %d disks on instance %s.", tc.raidLevel, activeDisks, publicIp)

			// --- Final Validation of Block Volumes via OCI SDK ---
			storageInstances := terraform.OutputListOfObjects(t, terraformOptions, "storage_instances")
			require.Len(t, storageInstances, 1, "Expected to find 1 storage instance")
			instanceID := storageInstances[0]["id"].(string)

			// Initialize OCI Config Provider
			configProvider := common.DefaultConfigProvider()
			
			// Create Core Service Client
			coreClient, err := core.NewComputeClientWithConfigurationProvider(configProvider)
			require.NoError(t, err, "Failed to create OCI compute client")

			// Get block volume attachments for the instance
			listVolumeAttachmentsRequest := core.ListVolumeAttachmentsRequest{
				CompartmentId: common.String(compartmentId),
				InstanceId:    common.String(instanceID),
			}

			listVolumeAttachmentsResponse, err := coreClient.ListVolumeAttachments(context.TODO(), listVolumeAttachmentsRequest)
			require.NoError(t, err, "Failed to list block volume attachments")

			expectedTotalVolumes := 1 + tc.diskCount // 1 boot volume + additional block volumes
			require.Len(t, listVolumeAttachmentsResponse.Items, expectedTotalVolumes, 
				"Incorrect number of block volumes attached to instance %s", instanceID)
			t.Logf("Successfully validated creation of %d total volumes for %s test.", expectedTotalVolumes, testName)
		})
	}
}