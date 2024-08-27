Push-Location $PSScriptRoot
try{
    Import-Module ./src/PSConsumerPipeline/PSConsumerPipeline.psd1 -force -Verbose
    if(-not $PublishApiKey){
        $PublishApiKey = Read-Host -Prompt "Specify NuGetApiKey" -MaskInput
    }
    if(Test-ModuleManifest -Path "./src/PSConsumerPipeline/PSConsumerPipeline.psd1" -Verbose){
        Publish-Module -Path "./src/PSConsumerPipeline/" -NuGetApiKey  $PublishApiKey -Verbose
    }
}
finally{
    Pop-Location
}
Update-Module PSConsumerPipeline -Force