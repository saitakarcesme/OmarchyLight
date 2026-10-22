import QtQuick
import Quickshell
import Quickshell.Io
import "AppSearch.js" as AppSearch

Item {
  id: library
  signal appsChanged()
  property var hiddenIds: ({})
  property var iconIndex: ({})
  property var normalized: ({})
  function originalIcon(icon) {
    const v=String(icon||"")
    if(v.startsWith("file:")||v.startsWith("image:"))return v
    if(v.startsWith("/"))return "file://"+v
    if(iconIndex[v])return "file://"+iconIndex[v]
    return Quickshell.iconPath(v||"application-x-executable",true)||Quickshell.iconPath("application-x-executable")
  }
  function entryName(entry) { return AppSearch.entryName(entry) }
  function entrySubtext(entry) { return AppSearch.entrySubtext(entry) }
  function sortedEntries(query) {
    return AppSearch.sortedEntries(DesktopEntries.applications.values,query,e=>hiddenIds[e.id]===true)
  }
  function iconSource(icon) {
    const original=originalIcon(icon)
    return normalized[original]||original
  }
  Process {
    id:normalize
    command:["python3",decodeURIComponent(Qt.resolvedUrl("normalize-icons.py").toString().replace("file://","")),
      JSON.stringify(library.sortedEntries("").map(e=>library.originalIcon(e.entry.icon)).filter(s=>s.startsWith("file:")))]
    stdout:StdioCollector {onStreamFinished:{try{library.normalized=JSON.parse(text)}catch(e){}}}
  }
  function refreshIcons() { if(!scan.running)scan.running=true }
  function launch(id,name) { Quickshell.execDetached(["uwsm-app","--","gtk-launch",id+".desktop"]) }
  function remove(id,name) { Quickshell.execDetached(["omarchy-remove-launcher-entry",id,name]) }
  Component.onCompleted:refreshIcons()
  Connections { target:DesktopEntries.applications;function onValuesChanged(){library.appsChanged();library.refreshIcons()} }
  Process {
    id:scan
    command:["python3",decodeURIComponent(Qt.resolvedUrl("icon-index.py").toString().replace("file://",""))]
    stdout:StdioCollector {onStreamFinished:{try{library.iconIndex=JSON.parse(text);if(!normalize.running)normalize.running=true}catch(e){}}}
  }
  FileView {
    path:(Quickshell.env("OMARCHY_PATH")||"/usr/share/omarchy")+"/default/omarchy/launcher.hides"
    printErrors:false;watchChanges:true
    onLoaded: {const ids={};for(const line of text().split("\n")){const id=line.trim().replace(/\.desktop$/,"");if(id&&!id.startsWith("#"))ids[id]=true}library.hiddenIds=ids;library.appsChanged()}
    onFileChanged:reload()
  }
}
