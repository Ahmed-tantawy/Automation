param (
    [Parameter(Mandatory=$true)]
    [decimal]$Baseline,
    
    [Parameter(Mandatory=$true)]
    [decimal]$Current,
    
    [Parameter(Mandatory=$true)]
    [decimal]$PercentDrop
)

# Format the values for better readability
$BaselineFormatted = [math]::Round($Baseline, 2)
$CurrentFormatted = [math]::Round($Current, 2)
$PercentDropFormatted = [math]::Round($PercentDrop, 2)

# Google Chat webhook URL - replace with your actual webhook URL
$WebhookUrl = "https://chat.google.com"

# Current timestamp
$Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

# Create the card message
$MessageBody = @{
  "cards" = @(
    @{
      "header" = @{
        "title" = "Jenkins Executor Alert"
        "subtitle" = "$PercentDropFormatted% reduction detected"
        "imageUrl" = "https://jenkins.io/images/logos/jenkins/jenkins.png"
      }
      "sections" = @(
        @{
          "widgets" = @(
            @{
              "keyValue" = @{
                "topLabel" = "Baseline (24h avg)"
                "content" = "$BaselineFormatted executors"
              }
            },
            @{
              "keyValue" = @{
                "topLabel" = "Current (1h avg)"
                "content" = "$CurrentFormatted executors"
              }
            },
            @{
              "keyValue" = @{
                "topLabel" = "Percentage Drop"
                "content" = "$PercentDropFormatted%"
              }
            },
            @{
              "keyValue" = @{
                "topLabel" = "Timestamp"
                "content" = "$Timestamp UTC"
              }
            }
          )
        },
        @{
          "widgets" = @(
            @{
              "textParagraph" = @{
                "text" = "This could indicate infrastructure issues or capacity problems requiring immediate attention."
              }
            }
          )
        },
        @{
          "widgets" = @(
            @{
              "textParagraph" = @{
                "text" = "<b>Recommended Actions:</b><br>1. Check Jenkins infrastructure health<br>2. Check Nodes with pool label availiabilty."
              }
            }
          )
        },
        @{
          "widgets" = @(
            @{
              "buttons" = @(
                @{
                  "textButton" = @{
                    "text" = "View Jenkins"
                    "onClick" = @{
                      "openLink" = @{
                        "url" = "http://localhost:8080/"  # Replace with your Jenkins URL
                      }
                    }
                  }
                }
              )
            }
          )
        }
      )
    }
  )
}

# Convert to JSON
$JsonBody = $MessageBody | ConvertTo-Json -Depth 10

# Log alert details to a file
$LogMessage = "[$Timestamp] ALERT: Jenkins executor drop detected. Baseline: $BaselineFormatted, Current: $CurrentFormatted, Drop: $PercentDropFormatted%"
$LogMessage | Out-File -FilePath "c:\elastalert2\service_logs\log" -Append

try {
    # Send the message to Google Chat
    $Response = Invoke-RestMethod -Uri $WebhookUrl -Method Post -Body $JsonBody -ContentType "application/json"
    
    # Log success
    "[$Timestamp] Successfully sent alert to Google Chat" | Out-File -FilePath "c:\elastalert2\service_logs\log" -Append
    
    # Return success
    Write-Output "Alert sent successfully to Google Chat"
} 
catch {
    # Log error
    "[$Timestamp] ERROR sending alert to Google Chat: $_" | Out-File -FilePath "c:\elastalert2\service_logs\log" -Append
    
    # Output error
    Write-Error "Failed to send alert: $_"
}
