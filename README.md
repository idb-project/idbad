# IDB AD 

Various small powershell cmdlets to funnel data into IDB.

# Some links

https://gallery.technet.microsoft.com/scriptcenter/0dbfc125-b855-4058-87ec-930268f03285#content

https://technet.microsoft.com/en-us/library/hh852328(v=wps.630).aspx

# Generate the installer

- install the wix-toolset: http://wixtoolset.org/
- put it in the PATH: https://msdn.microsoft.com/de-de/library/gg513936.aspx
- candle.exe idbad.wxs
- light.exe idbad.wixobj