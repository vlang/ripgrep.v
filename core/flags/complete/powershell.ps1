using namespace System.Management.Automation
using namespace System.Management.Automation.Language

Register-ArgumentCompleter -Native -CommandName 'rg' -ScriptBlock {
  param($wordToComplete, $commandAst, $cursorPosition)
  $commandElements = $commandAst.CommandElements
  $command = @(
    'rg'
    for ($i = 1; $i -lt $commandElements.Count; $i++) {
        $element = $commandElements[$i]
        if ($element -isnot [StringConstantExpressionAst] -or
            $element.StringConstantType -ne [StringConstantType]::BareWord -or
            $element.Value.StartsWith('-')) {
            break
    }
    $element.Value
  }) -join ';'

  $completions = @(switch ($command) {
    'rg' {
!FLAGS!
    }
  })

  $completions.Where{ $_.CompletionText -like "$wordToComplete*" } |
    Sort-Object -Property ListItemText
}
