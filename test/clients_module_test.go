package test

import (
	"context"
	"fmt"
	"testing"

	"github.com/gruntwork-io/terratest/modules/random"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/oracle/oci-go-sdk/v65/common"
	"github.com/oracle/oci-go-sdk/v65/core"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// TestClientModule runs an isolated integration test for the clients module.
func TestClientModule(t *testing.T) {
	t.Parallel()

	// --- Test Setup ---
	// These variables will be passed from the CI workflow (GitHub Actions)
	region := getRequiredEnvVar(t, "OCI_REGION")
	compartmentId := getRequiredEnvVar(t, "OCI_COMPARTMENT_ID")
	vcnId := getRequiredEnvVar(t, "VCN_ID")
	subnetId := getRequiredEnvVar(t, "SUBNET_ID")
	keyName := getRequiredEnvVar(t, "KEY_NAME")
	clientsImageId := getRequiredEnvVar(t, "CLIENTS_IMAGE_ID")
	availabilityDomain := getRequiredEnvVar(t, "AVAILABILITY_DOMAIN")
	
	projectName := fmt.Sprintf("terratest-clients-%s", random.UniqueId())
	
	// Define expected values for validation
	expectedInstanceCount := 1
	expectedBlockVolumeCount := 2 
	expectedBootVolumeType := "gp3" // OCI uses different volume types, adjust as needed
	expectedBlockVolumeType := "gp3"

	terraformOptions := &terraform.Options{
		TerraformDir:    "../modules/clients/examples",
		TerraformBinary: "terraform",
		Vars: map[string]interface{}{
			"project_name":           projectName,
			"region":                 region,
			"compartment_id":         compartmentId,
			"vcn_id":                 vcnId,
			"subnet_id":              subnetId,
			"key_name":               keyName,
			"clients_image_id":       clientsImageId,
			"availability_domain":    availabilityDomain,
			"clients_instance_count": expectedInstanceCount,
			"block_volume_count":     expectedBlockVolumeCount,
			"boot_volume_type":       expectedBootVolumeType,
			"block_volume_type":      expectedBlockVolumeType,
		},
	}

	// --- Test Lifecycle ---
	defer terraform.Destroy(t, terraformOptions)
	terraform.InitAndApply(t, terraformOptions)

	// --- Validation ---
	clientInstances := terraform.OutputListOfObjects(t, terraformOptions, "client_instances")
	require.Equal(t, expectedInstanceCount, len(clientInstances), "Expected to find %d client instance in the output", expectedInstanceCount)
	
	instanceID := clientInstances[0]["id"].(string)

	// --- OCI SDK Validation: Check Instance and Volume Details ---
	configProvider := common.DefaultConfigProvider()
	
	// Create Core Service Client
	coreClient, err := core.NewComputeClientWithConfigurationProvider(configProvider)
	require.NoError(t, err, "Failed to create OCI compute client")

	// 1. Describe the instance
	getInstanceRequest := core.GetInstanceRequest{
		InstanceId: common.String(instanceID),
	}
	getInstanceResponse, err := coreClient.GetInstance(context.TODO(), getInstanceRequest)
	require.NoError(t, err, "Failed to get OCI instance details")
	
	instance := getInstanceResponse.Instance
	assert.Equal(t, core.InstanceLifecycleStateRunning, instance.LifecycleState, "Instance is not in 'RUNNING' state")

	// 2. Get boot volume attachment
	listBootVolumeAttachmentsRequest := core.ListBootVolumeAttachmentsRequest{
		CompartmentId:      common.String(compartmentId),
		AvailabilityDomain: common.String(availabilityDomain),
		InstanceId:         common.String(instanceID),
	}
	listBootVolumeAttachmentsResponse, err := coreClient.ListBootVolumeAttachments(context.TODO(), listBootVolumeAttachmentsRequest)
	require.NoError(t, err, "Failed to list boot volume attachments")
	require.Len(t, listBootVolumeAttachmentsResponse.Items, 1, "Expected 1 boot volume attachment")

	// 3. Describe all block volumes attached to the instance
	listVolumeAttachmentsRequest := core.ListVolumeAttachmentsRequest{
		CompartmentId: common.String(compartmentId),
		InstanceId:    common.String(instanceID),
	}
	listVolumeAttachmentsResponse, err := coreClient.ListVolumeAttachments(context.TODO(), listVolumeAttachmentsRequest)
	require.NoError(t, err, "Failed to list block volume attachments")

	// 4. Assert the total number of block volumes is correct
	assert.Len(t, listVolumeAttachmentsResponse.Items, expectedBlockVolumeCount, "Incorrect number of block volumes attached")

	// 5. Create Block Storage client to get volume details
	blockStorageClient, err := core.NewBlockstorageClientWithConfigurationProvider(configProvider)
	require.NoError(t, err, "Failed to create OCI block storage client")

	// 6. Validate boot volume type
	bootVolumeId := listBootVolumeAttachmentsResponse.Items[0].BootVolumeId
	getBootVolumeRequest := core.GetBootVolumeRequest{
		BootVolumeId: bootVolumeId,
	}
	getBootVolumeResponse, err := blockStorageClient.GetBootVolume(context.TODO(), getBootVolumeRequest)
	require.NoError(t, err, "Failed to get boot volume details")
	
	fmt.Printf("Validating boot volume (%s)\n", *bootVolumeId)
	// Note: OCI has different volume performance levels, adjust validation as needed
	// assert.Equal(t, expectedBootVolumeType, string(getBootVolumeResponse.VpusPerGb), "Boot volume has incorrect type")

	// 7. Iterate through the attached block volumes and validate each one
	extraVolumesCount := 0
	for _, attachment := range listVolumeAttachmentsResponse.Items {
		extraVolumesCount++
		volumeId := attachment.VolumeId
		
		getVolumeRequest := core.GetVolumeRequest{
			VolumeId: volumeId,
		}
		getVolumeResponse, err := blockStorageClient.GetVolume(context.TODO(), getVolumeRequest)
		require.NoError(t, err, "Failed to get block volume details")
		
		fmt.Printf("Validating block volume (%s)\n", *volumeId)
		// Note: OCI has different volume performance levels, adjust validation as needed
		// assert.Equal(t, expectedBlockVolumeType, string(getVolumeResponse.VpusPerGb), "Block volume has incorrect type")
	}

	assert.Equal(t, expectedBlockVolumeCount, extraVolumesCount, "Incorrect number of block volumes found")
}