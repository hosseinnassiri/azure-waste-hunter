# Azure cleanup candidates for ops@example.com

1 finding(s), about 103.51 CAD per month (1 high confidence). From a read-only scan on 2026-11-27: nothing in Azure was changed. Please check each one and act on what you agree with; reply if something must stay, and it will be excluded with your reason.

- **vm-win-jumpbox** (VMs stopped but not deallocated, rg-ops): 103.51 CAD/month, high confidence. Power state is Stopped (not deallocated), so compute is still billed. Suggested: Deallocate it to stop compute billing (its disks keep billing), or delete it if it's no longer needed. Deallocating releases dynamic public IPs. [Portal](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-ops/providers/Microsoft.Compute/virtualMachines/vm-win-jumpbox)

