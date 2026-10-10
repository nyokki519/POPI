#!/usr/bin/env python3
"""Generate a dependency-free Xcode project; no XcodeGen/Homebrew required."""
from pathlib import Path
import hashlib,json,plistlib
root=Path(__file__).resolve().parents[1]
objects={}
def ident(name):return hashlib.sha256(name.encode()).hexdigest()[:24].upper()
def obj(keyname,isa,**fields):
    key=ident(keyname);objects[key]={'isa':isa,**fields};return key

def configlist(name,base):
    configs=[]
    for mode in ('Debug','Release'):
        configs.append(obj(name+mode,'XCBuildConfiguration',name=mode,buildSettings={**base,'SWIFT_OPTIMIZATION_LEVEL':'-Onone' if mode=='Debug' else '-O'}))
    return obj(name+'configs','XCConfigurationList',buildConfigurations=configs,defaultConfigurationIsVisible='0',defaultConfigurationName='Release')
products=[];targets=[];targetids={name:ident(name+'target') for name in ('GravityReader','Upload')}
fileids={}
for p in sorted((root/'Sources').rglob('*.swift')):
    rel=str(p.relative_to(root));fileids[rel]=obj(rel,'PBXFileReference',lastKnownFileType='sourcecode.swift',path=rel,sourceTree='<group>')
for name in targetids:
    app=name=='GravityReader'
    identifier='jp.nyokki519.GravityReader'+('' if app else '.'+name)
    info={'CFBundleDevelopmentRegion':'ja','CFBundleExecutable':'$(EXECUTABLE_NAME)','CFBundleIdentifier':'$(PRODUCT_BUNDLE_IDENTIFIER)','CFBundleInfoDictionaryVersion':'6.0','CFBundleName':'$(PRODUCT_NAME)','CFBundlePackageType':'APPL' if app else 'XPC!','CFBundleShortVersionString':'0.1','CFBundleVersion':'1','CFBundleDisplayName':'Gravity Reader' if app or name=='Setup' else 'Gravity Reader PRIVATE'}
    if app:info.update(UILaunchScreen={},UISupportedInterfaceOrientations=['UIInterfaceOrientationPortrait'])
    else:
        attrs={'RPBroadcastExtension':'jp.nyokki519.GravityReader.Upload'} if name=='Setup' else {'RPBroadcastProcessMode':'RPBroadcastProcessModeSampleBuffer'}
        info['NSExtension']={'NSExtensionPointIdentifier':'com.apple.broadcast-services-'+('setupui' if name=='Setup' else 'upload'),'NSExtensionPrincipalClass':'$(PRODUCT_MODULE_NAME).'+('SetupViewController' if name=='Setup' else 'SampleHandler'),'NSExtensionAttributes':attrs}
    (root/(name+'-Info.plist')).write_bytes(plistlib.dumps(info))
    product=obj(name+'product','PBXFileReference',explicitFileType='wrapper.application' if app else 'wrapper.app-extension',includeInIndex='0',path=name+('.app' if app else '.appex'),sourceTree='BUILT_PRODUCTS_DIR');products.append(product)
    sources=[]
    for rel,fid in fileids.items():
        if '/'+('App' if app else name)+'/' in rel or (not app and '/Shared/' in rel and (name=='Upload' or rel.endswith('Configuration.swift'))):
            sources.append(obj(name+rel+'build','PBXBuildFile',fileRef=fid))
    phases=[obj(name+'sources','PBXSourcesBuildPhase',buildActionMask='2147483647',files=sources,runOnlyForDeploymentPostprocessing='0'),obj(name+'frameworks','PBXFrameworksBuildPhase',buildActionMask='2147483647',files=[],runOnlyForDeploymentPostprocessing='0')]
    deps=[]
    if app:
        embeds=[]
        for ext in ('Upload',):
            proxy=obj(ext+'proxy','PBXContainerItemProxy',containerPortal=ident('project'),proxyType='1',remoteGlobalIDString=targetids[ext],remoteInfo=ext)
            deps.append(obj(ext+'dep','PBXTargetDependency',target=targetids[ext],targetProxy=proxy))
            embeds.append(obj(ext+'embed','PBXBuildFile',fileRef=ident(ext+'product'),settings={'ATTRIBUTES':['RemoveHeadersOnCopy']}))
        phases.append(obj('embed','PBXCopyFilesBuildPhase',buildActionMask='2147483647',dstPath='',dstSubfolderSpec='13',files=embeds,name='Embed App Extensions',runOnlyForDeploymentPostprocessing='0'))
    settings={'PRODUCT_NAME':name,'PRODUCT_BUNDLE_IDENTIFIER':identifier,'INFOPLIST_FILE':name+'-Info.plist','SWIFT_VERSION':'5.0','IPHONEOS_DEPLOYMENT_TARGET':'16.0','TARGETED_DEVICE_FAMILY':'1,2','CODE_SIGN_STYLE':'Automatic','SDKROOT':'iphoneos','LD_RUNPATH_SEARCH_PATHS':['$(inherited)','@executable_path/Frameworks']+([] if app else ['@executable_path/../../Frameworks'])}
    if not app:settings.update(APPLICATION_EXTENSION_API_ONLY='YES',SKIP_INSTALL='YES')
    targets.append(obj(name+'target','PBXNativeTarget',buildConfigurationList=configlist(name,settings),buildPhases=phases,buildRules=[],dependencies=deps,name=name,productName=name,productReference=product,productType='com.apple.product-type.'+('application' if app else 'app-extension')))
pg=obj('products','PBXGroup',children=products,name='Products',sourceTree='<group>')
mg=obj('main','PBXGroup',children=list(fileids.values())+[pg],sourceTree='<group>')
project=obj('project','PBXProject',attributes={'LastUpgradeCheck':'1600'},buildConfigurationList=configlist('project',{'CLANG_ENABLE_MODULES':'YES'}),compatibilityVersion='Xcode 14.0',developmentRegion='ja',hasScannedForEncodings='0',knownRegions=['ja','en','Base'],mainGroup=mg,productRefGroup=pg,projectDirPath='',projectRoot='',targets=targets)
def format_value(v):
    if isinstance(v,dict):return '{ '+ ' '.join(f'{format_value(k)} = {format_value(x)};' for k,x in v.items())+' }'
    if isinstance(v,list):return '('+','.join(format_value(x) for x in v)+',)' if v else '()'
    return json.dumps(str(v),ensure_ascii=False)
p=root/'GravityReader.xcodeproj';p.mkdir(exist_ok=True)
(p/'project.pbxproj').write_text('// !$*UTF8*$!\n'+format_value({'archiveVersion':'1','classes':{},'objectVersion':'56','objects':objects,'rootObject':project})+'\n')
s=p/'xcshareddata/xcschemes';s.mkdir(parents=True,exist_ok=True)
ref=f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{targetids["GravityReader"]}" BuildableName="GravityReader.app" BlueprintName="GravityReader" ReferencedContainer="container:GravityReader.xcodeproj"/>'
(s/'GravityReader.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?><Scheme LastUpgradeVersion="1600" version="1.3"><BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{ref}</BuildActionEntry></BuildActionEntries></BuildAction><LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{ref}</BuildableProductRunnable></LaunchAction><ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{ref}</BuildableProductRunnable></ProfileAction><AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/></Scheme>''')
print('Generated',p)
