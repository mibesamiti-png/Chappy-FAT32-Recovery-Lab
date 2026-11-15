#requires -Version 5.1
# Team B R8-P4: generated-only read-only handle lease; NEVER permits writing.
Set-StrictMode -Version Latest

function Initialize-ChappyBR8Native {
    if('ChappyBR8RootLeaseNativeV1' -as [type]){return}
    $nativeSource=@'
using System;
using System.Text;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

// Windows APIs: CreateFileW (OPEN_REPARSE_POINT + BACKUP_SEMANTICS),
// GetFileInformationByHandle (volume/index), GetFinalPathNameByHandleW.
// No actual source FileStream or output writer in this module.
public sealed class ChappyBR8RootLeaseNativeV1 : IDisposable {
    [StructLayout(LayoutKind.Sequential)]
    private struct FT { public uint Low; public uint High; }
    [StructLayout(LayoutKind.Sequential)]
    private struct FI {
        public uint Attr;
        public FT Created; public FT Accessed; public FT Written;
        public uint Volume; public uint SizeHi; public uint SizeLo;
        public uint Links; public uint IdHi; public uint IdLo;
    }
    [DllImport("kernel32.dll", EntryPoint="CreateFileW", CharSet=CharSet.Unicode, SetLastError=true)]
    private static extern SafeFileHandle OpenFile(string path, uint access, uint shares,
        IntPtr security, uint disposition, uint flags, IntPtr templateHandle);
    [DllImport("kernel32.dll", SetLastError=true)]
    private static extern bool GetFileInformationByHandle(SafeFileHandle h, out FI info);
    [DllImport("kernel32.dll", EntryPoint="GetFinalPathNameByHandleW",
        CharSet=CharSet.Unicode, SetLastError=true)]
    private static extern uint GetFinalPathNameByHandle(SafeFileHandle h,
        StringBuilder name, uint size, uint flags);

    private const uint READ_ATTRIBUTES=0x80;
    private const uint SHARE_READ_WRITE=0x03; // no FILE_SHARE_DELETE
    private const uint OPEN_EXISTING=3;
    private const uint DIRECTORY_NOFOLLOW=0x02000000 | 0x00200000;
    private const uint DIRECTORY=0x10, REPARSE=0x400;
    private SafeFileHandle parentHandle, rootHandle;
    private FI parentId, rootId;
    private string parentPath, rootPath;
    private bool disposed;

    private ChappyBR8RootLeaseNativeV1(string parent,string root){
        parentPath=parent;rootPath=root;
    }
    private static SafeFileHandle OpenDirectory(string p) {
        return OpenFile(p, READ_ATTRIBUTES, SHARE_READ_WRITE,
            IntPtr.Zero, OPEN_EXISTING, DIRECTORY_NOFOLLOW, IntPtr.Zero);
    }
    private static bool Same(FI a,FI b) {
        return a.Volume==b.Volume && a.IdHi==b.IdHi && a.IdLo==b.IdLo;
    }
    private static string Resolved(SafeFileHandle h) {
        StringBuilder b=new StringBuilder(32768);
        uint n=GetFinalPathNameByHandle(h,b,(uint)b.Capacity,0);
        if(n==0 || n>=(uint)b.Capacity)return null;
        string path=b.ToString();
        if(!path.StartsWith(@"\\?\",StringComparison.Ordinal))return null;
        path=path.Substring(4);
        if(path.Length<3 || path[1]!=':' || path[2]!='\\')return null;
        return path.TrimEnd('\\');
    }
    private static bool Inspect(SafeFileHandle h,string expected,out FI i) {
        i=new FI();
        if(h==null || h.IsInvalid || h.IsClosed)return false;
        if(!GetFileInformationByHandle(h,out i))return false;
        if((i.Attr & DIRECTORY)==0 || (i.Attr & REPARSE)!=0)return false;
        string actual=Resolved(h);
        return actual!=null && String.Equals(actual,expected,StringComparison.OrdinalIgnoreCase);
    }
    private static ChappyBR8RootLeaseNativeV1 Reject(ChappyBR8RootLeaseNativeV1 x){
        x.Dispose();return null;
    }
    public static ChappyBR8RootLeaseNativeV1 TryOpen(string parent,string root){
        ChappyBR8RootLeaseNativeV1 x=null;
        try{
            x=new ChappyBR8RootLeaseNativeV1(parent,root);
            x.parentHandle=OpenDirectory(parent);
            if(!Inspect(x.parentHandle,parent,out x.parentId))return Reject(x);
            x.rootHandle=OpenDirectory(root);
            if(!Inspect(x.rootHandle,root,out x.rootId))return Reject(x);
            if(x.parentId.Volume!=x.rootId.Volume || !x.IsStable())return Reject(x);
            return x;
        }catch{if(x!=null)x.Dispose();return null;}
    }
    // Compare the same open object, then independent open of each named object.
    // Prevents returning a false positive after ordinary path replacement;
    // does not authorize a subsequent pathname CreateNew.
    public bool IsStable(){
        if(disposed || parentHandle==null || rootHandle==null)return false;
        SafeFileHandle p=null,r=null;
        try{
            FI a,b,c,d;
            if(!Inspect(parentHandle,parentPath,out a) ||
               !Inspect(rootHandle,rootPath,out b) ||
               !Same(parentId,a) || !Same(rootId,b))return false;
            p=OpenDirectory(parentPath);r=OpenDirectory(rootPath);
            if(!Inspect(p,parentPath,out c) || !Inspect(r,rootPath,out d))return false;
            return Same(parentId,c) && Same(rootId,d);
        }catch{return false;}
        finally{if(r!=null)r.Dispose();if(p!=null)p.Dispose();}
    }
    public bool StoredRootIsSameObject(ChappyBR8RootLeaseNativeV1 other){
        return other!=null && Same(rootId,other.rootId);
    }
    public bool IsClosed {get{return disposed;}}
    public void Dispose(){
        if(disposed)return;disposed=true;
        if(rootHandle!=null){rootHandle.Dispose();rootHandle=null;}
        if(parentHandle!=null){parentHandle.Dispose();parentHandle=null;}
    }
}
'@
    Add-Type -TypeDefinition $nativeSource -ErrorAction Stop
}

function New-ChappyBR8GuardResult {
    param([string]$Status='unsafe_root',[string]$Decision='UNKNOWN',
          [bool]$Verified=$false,[object]$Lease=$null,
          [string]$Reason='r8.p4_unverifiable_root')
    return [pscustomobject]@{
        schemaVersion='b_r8_root_handle_guard_v1'
        team='B';status=$Status;decision=$Decision
        handleIdentityVerified=$Verified
        guarantee='preflight_only_not_relative_create'
        canAuthorizeWrite=$false;canExportOriginal=$false
        originalIdentity='unknown';sourceAuthenticity='not_proven'
        rootPathPublic=$null
        warningCodes=@($Reason)
        # Opaque IDisposable object, NEVER include in a public JSON/log.
        lease=$Lease
        metrics=[pscustomobject]@{
            sourceReadCalls=0;sourceReturnedBytes=0L
            outputFilesCreated=0;outputBytesWritten=0L;filesDeleted=0
        }
    }
}

function Get-ChappyBR8AllowedTempRoot {
    param([string]$OutputRoot)
    if([string]::IsNullOrWhiteSpace($OutputRoot) -or
       $OutputRoot.Length -gt 240 -or
       $OutputRoot -cnotmatch '^[A-Za-z]:\\' -or
       $OutputRoot -match '[/\\]\.\.?([/\\]|$)' -or
       ($OutputRoot.Length -gt 2 -and $OutputRoot.Substring(2).Contains(':'))){
        return $null
    }
    try{
        $full=[IO.Path]::GetFullPath($OutputRoot).TrimEnd([char[]]@('\','/'))
        $temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([char[]]@('\','/'))
        $parent=[IO.Path]::GetDirectoryName($full)
        $leaf=[IO.Path]::GetFileName($full)
        if($leaf -cnotmatch '^ChappyR8Synthetic-[0-9a-f]{32}$' -or
           -not [string]::Equals($parent,$temp,[StringComparison]::OrdinalIgnoreCase) -or
           -not [IO.Directory]::Exists($full)){return $null}
        foreach($location in @($temp,$full)){
            $node=[IO.DirectoryInfo]::new($location)
            for($depth=0;$null -ne $node;$depth++){
                if($depth -ge 64){return $null}
                $attrs=[IO.File]::GetAttributes($node.FullName)
                if(($attrs -band [IO.FileAttributes]::Directory) -eq 0 -or
                   ($attrs -band [IO.FileAttributes]::ReparsePoint) -ne 0){
                    return $null
                }
                $node=$node.Parent
            }
        }
        return [pscustomobject]@{temp=$temp;root=$full}
    }catch{return $null}
}

function Open-ChappyR8SyntheticRootLeaseV1 {
    [CmdletBinding(PositionalBinding=$false)]
    param([string]$OutputRoot='',[switch]$EnableSyntheticRootGuard)
    if(-not $EnableSyntheticRootGuard){
        return New-ChappyBR8GuardResult -Status 'disabled' -Decision 'not_requested' -Reason 'r8.p4_optin_required'
    }
    if($env:OS -cne 'Windows_NT' -or $PSVersionTable.PSVersion.Major -ne 5 -or
       $PSVersionTable.PSVersion.Minor -ne 1){
        return New-ChappyBR8GuardResult -Reason 'r8.p4_windows_5_1_required'
    }
    $safe=Get-ChappyBR8AllowedTempRoot -OutputRoot $OutputRoot
    if($null -eq $safe){
        return New-ChappyBR8GuardResult -Reason 'r8.p4_invalid_temp_root'
    }
    $lease=$null
    try{
        Initialize-ChappyBR8Native
        $lease=[ChappyBR8RootLeaseNativeV1]::TryOpen([string]$safe.temp,[string]$safe.root)
        if($null -eq $lease){return New-ChappyBR8GuardResult -Reason 'r8.p4_native_handle_unknown'}
        $secondCheck=Get-ChappyBR8AllowedTempRoot -OutputRoot $OutputRoot
        if($null -eq $secondCheck -or -not $lease.IsStable()){
            $lease.Dispose()
            return New-ChappyBR8GuardResult -Reason 'r8.p4_root_changed_or_identity_unknown'
        }
        return New-ChappyBR8GuardResult -Status 'handle_observed' -Decision 'HANDLE_OBSERVED_PREFLIGHT_ONLY' -Verified $true -Lease $lease -Reason 'r8.p4_no_write_authority'
    }catch{
        if($null -ne $lease){$lease.Dispose()}
        return New-ChappyBR8GuardResult -Reason 'r8.p4_native_api_unknown'
    }
}

function Test-ChappyR8SyntheticRootLeaseV1 {
    [CmdletBinding(PositionalBinding=$false)]
    param([Parameter(Mandatory)][psobject]$GuardResult)
    try{
        if($GuardResult.schemaVersion -cne 'b_r8_root_handle_guard_v1' -or
           $null -eq $GuardResult.lease -or
           -not ($GuardResult.lease -is [ChappyBR8RootLeaseNativeV1]) -or
           $GuardResult.lease.IsClosed -or -not $GuardResult.lease.IsStable()){
            return New-ChappyBR8GuardResult -Reason 'r8.p4_lease_closed_or_root_changed'
        }
        return New-ChappyBR8GuardResult -Status 'handle_observed' -Decision 'HANDLE_OBSERVED_PREFLIGHT_ONLY' -Verified $true -Reason 'r8.p4_no_write_authority'
    }catch{return New-ChappyBR8GuardResult -Reason 'r8.p4_handle_recheck_unknown'}
}

function Close-ChappyR8SyntheticRootLeaseV1 {
    [CmdletBinding(PositionalBinding=$false)]
    param([Parameter(Mandatory)][psobject]$GuardResult)
    try{
        if($null -ne $GuardResult.lease -and
           $GuardResult.lease -is [ChappyBR8RootLeaseNativeV1]){
            $GuardResult.lease.Dispose()
        }
    }catch{}
    return New-ChappyBR8GuardResult -Status 'closed' -Decision 'not_authorized' -Reason 'r8.p4_lease_closed'
}

Export-ModuleMember -Function Open-ChappyR8SyntheticRootLeaseV1,Test-ChappyR8SyntheticRootLeaseV1,Close-ChappyR8SyntheticRootLeaseV1
