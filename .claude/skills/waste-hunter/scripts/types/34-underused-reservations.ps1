# waste-hunter 34 · Reservations whose prepaid hours go unused (no query: Collect)
# Reservations aren't in Resource Graph, so this type has no .kql file. Its Collect block reads
# 'az consumption reservation summary list' (reserved vs used hours, daily, 30 days) for each order in
# $ReservationOrders: the -ReservationOrder IDs plus any order named in the usage records the scan
# read for billed cost. Only hours and the SKU are read from the output.
# Loaded by Import-WasteTypes (lib/WasteTypes.ps1); the runner calls Collect once per scan.

@{
    Name = 'underused-reservation'
    Label = 'Underused reservations'
    Order = 34
    Collect = {
        $rows = @()
        foreach ($o in @($ReservationOrders | Sort-Object)) {
            try {
                $days = @(Invoke-AzRead @('consumption', 'reservation', 'summary', 'list', '--grain', 'daily', '--reservation-order-id', $o,
                    '--start-date', $Now.AddDays(-30).ToString('yyyy-MM-dd'), '--end-date', $Now.ToString('yyyy-MM-dd')) | Where-Object { $_ })
            }
            catch {
                # Unreadable (another tenant, or no Reservations Reader role): left out of $CollectScopes,
                # so its earlier findings are "not rechecked", never "resolved"
                $warnings.Add("Couldn't read the utilization of reservation order ${o}: $($_.Exception.Message)")
                continue
            }
            [void] $CollectScopes['underused-reservation'].Add("/providers/microsoft.capacity/reservationorders/$o")
            foreach ($g in @($days | Group-Object { ([string] (Get-Key $_ 'reservationId') -split '/')[-1].ToLower() })) {
                $reserved = [double] (($g.Group | ForEach-Object { [double] ((Get-Key $_ 'reservedHours') ?? 0) } | Measure-Object -Sum).Sum ?? 0)
                $used = [double] (($g.Group | ForEach-Object { [double] ((Get-Key $_ 'usedHours') ?? 0) } | Measure-Object -Sum).Sum ?? 0)
                if ($reserved -le 0) { continue }
                $util = $used / $reserved * 100
                if ($util -ge 80) { continue }
                $first = $g.Group[0]
                # The summary has no kind or quantity: reservationId, reservationOrderId, skuName, usageDate,
                # reservedHours, usedHours and min/avg/max utilization (checked against the CLI's schema)
                $sku = [string] (Get-Key $first 'skuName')
                $rid = $g.Name
                $rows += [ordered]@{
                    wasteType = 'underused-reservation'; id = "/providers/Microsoft.Capacity/reservationOrders/$o/reservations/$rid"
                    name = "$($sku ? $sku : 'reservation') ($($rid.Substring(0, [math]::Min(8, $rid.Length))))"; type = 'microsoft.capacity/reservationorders/reservations'
                    tenantId = [string] $original.tenantId; subscriptionId = ''; resourceGroup = ''; location = ''; owner = ''; app = ''; env = ''
                    createdTime = ''; ageDays = $null; idleDays = $null; idleSource = 'reservation summary (reserved vs used hours), 30 days'
                    sku = $sku; tier = ''; sizeGb = $null; os = ''; extra = $o
                    confidence = ($util -lt 50) ? 'high' : 'medium'
                    reason = ('Used {0:N0}% of its reserved hours in the last 30 days ({1:N0} of {2:N0} hours). The unused hours are prepaid and lost' -f $util, $used, $reserved)
                    ignored = 0; utilization = $util
                }
            }
        }
        return $rows
    }
    Estimate = { return @{ Cost = $null; Note = 'the reservation price is not readable with the allowed commands; the unused share of it is the waste' } }
    Action = {
        return @(
            'Find what it was bought for in the portal (Reservations > Utilization). Widen its scope to shared or a management group so more resources can use it, exchange it for a size or region that runs now, or let it lapse at renewal. Unused hours are not refunded.',
            '')
    }
}
