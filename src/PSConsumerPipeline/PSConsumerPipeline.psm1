Function Invoke-ConsumerPipeline
{
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline=$true)][psobject[]]$Item,
        [Parameter()][ScriptBlock]$ProcessBlock,
        [Parameter()][int]$MaxWorkers=8,
        [Parameter()][int]$OutputBufferSize=100
    )
    begin{
        $InputQueue = [System.Collections.Concurrent.BlockingCollection[PSObject]]::new($OutputBufferSize)
        $OutputQueue = [System.Collections.Concurrent.BlockingCollection[PSObject]]::new()
        $RunspacePool = [runspacefactory]::CreateRunspacePool(1,$MaxWorkers,$Host)
        $RunspacePool.Open()
        $Runspaces = @(1..$MaxWorkers)|foreach-object  {
            write-verbose "Staring worker $_"
            $Runspace = [PowerShell]::Create().AddScript([ScriptBlock]{
                param(
                    [System.Collections.Concurrent.BlockingCollection[PSObject]]$inputCollection,
                    [System.Collections.Concurrent.BlockingCollection[PSObject]]$outputCollection,
                    [ScriptBlock]$ProcessBlock
                )
                $inputCollection.GetConsumingEnumerable()|foreach-object{
                    $x=$_
                    try{
                        $result = $ProcessBlock.Ast.GetScriptBlock().Invoke($x)
                        $outputCollection.Add((new-object psobject -Property @{
                            Input=$x
                            Result=$result
                            Error=$null
                            IsSuccessful=$true
                        }))
                    }
                    catch{
                        $outputCollection.Add((new-object psobject -Property @{
                            Input=$x
                            Error=$_
                            IsSuccessful=$false
                        }))
                    }                    
                }
            }).AddArgument($InputQueue).AddArgument($OutputQueue).AddArgument($ProcessBlock)
            $Runspace.RunspacePool = $RunspacePool
            $Handle = $Runspace.BeginInvoke()
            New-Object psobject -Property @{
                Runspace = $Runspace
                Handle = $Handle
            }
        }
    }
    process{
        $Item|ForEach-Object{
            [PSObject]$x=$null
            if($OutputQueue.Count -ge $OutputBufferSize){
                while($OutputQueue.TryTake([ref]$x,10))
                {
                    $x|Write-Output
                }                
            }
            write-verbose "Adding item $_"
            $InputQueue.Add($_)
            write-verbose "Item $_ added"
        }
    }
    end{
        write-verbose "Complete Adding: Remaining items: $($InputQueue.Count)"
        $InputQueue.CompleteAdding()
        write-verbose "Completing $($Runspaces.Count) workers."
        $Runspaces|foreach-object {
            $_.Runspace.EndInvoke($_.Handle)
            $_.Runspace.Dispose()
        }
        $RunspacePool.Close()
        $RunspacePool.Dispose()
        write-verbose "Remaining items: $($InputQueue.Count)"
        $OutputQueue.CompleteAdding()
        $OutputQueue.GetConsumingEnumerable()|Write-Output
    }
}