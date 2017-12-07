function Search-Binary {
    [cmdletbinding()]
    Param (
        [parameter(ValueFromPipeline=$True,ValueFromPipelineByPropertyName=$True,Mandatory=$True)]
        $ByteArray,
        [parameter(ValueFromPipeline=$True,ValueFromPipelineByPropertyName=$True,Mandatory=$True)]
        [Byte[]]$Pattern,
        [parameter(ValueFromPipeline=$True,ValueFromPipelineByPropertyName=$True)]
        [Switch]$First
    )
    
    #  Original method function originally by Tommaso Belluzzo
    #  https://stackoverflow.com/questions/16252518/boyer-moore-horspool-algorithm-for-all-matches-find-byte-array-inside-byte-arra
    $MethodDefinition = @'

        public static System.Collections.Generic.List<Int64> IndexesOf(Byte[] ByteArray, Byte[] pattern, bool first = false)
        {
            if (ByteArray == null)
                throw new ArgumentNullException("ByteArray");

            if (pattern == null)
                throw new ArgumentNullException("pattern");

            Int64 ByteArrayLength = ByteArray.LongLength;
            Int64 patternLength = pattern.LongLength;
            Int64 searchLength = ByteArrayLength - patternLength;

            if ((ByteArrayLength == 0) || (patternLength == 0) || (patternLength > ByteArrayLength))
                return (new System.Collections.Generic.List<Int64>());

            Int64[] badCharacters = new Int64[256];

            for (Int64 i = 0; i < 256; ++i)
                badCharacters[i] = patternLength;

            Int64 lastPatternByte = patternLength - 1;

            for (Int64 i = 0; i < lastPatternByte; ++i)
                badCharacters[pattern[i]] = lastPatternByte - i;

            // Beginning

            Int64 index = 0;
            System.Collections.Generic.List<Int64> indexes = new System.Collections.Generic.List<Int64>();

            while (index <= searchLength)
            {
                for (Int64 i = lastPatternByte; ByteArray[(index + i)] == pattern[i]; --i)
                {
                    if (i == 0)
                    {
                        indexes.Add(index);
                        if (first)
                            return indexes;
                        break;
                    }
                }

                index += badCharacters[ByteArray[(index + lastPatternByte)]];
            }

            return indexes;
        }
'@

    if (-not ([System.Management.Automation.PSTypeName]'Random.Search').Type) {
        Add-Type -MemberDefinition $MethodDefinition -Name 'Search' -Namespace 'Random' | Out-Null
    }
    return [Random.Search]::IndexesOf($ByteArray, $Pattern, $First)
}