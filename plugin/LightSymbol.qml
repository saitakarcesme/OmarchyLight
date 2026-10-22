import QtQuick
import QtQuick.Window
Image {
    property string kind: "search"
    property color ink: kind==="apps"?"#96969a":"#8b8b90"
    sourceSize: Qt.size(Math.max(1,Math.round(width*Math.max(2,Screen.devicePixelRatio))), Math.max(1,Math.round(height*Math.max(2,Screen.devicePixelRatio))))
    smooth: true
    fillMode: Image.PreserveAspectFit
    source: "data:image/svg+xml;utf8," + encodeURIComponent(mark())
    function mark() {
        const paths={
            search:'<circle cx="10" cy="10" r="8"/><path d="m16 16 6 6"/>',
            apps:'<g stroke-width="2.7"><path d="m10 5 1.5 2.6M14 5 6.5 18M4.8 20.9l-.5.9M3.4 17h11M14.4 11.4l6 10.4M18.4 17H21"/></g>',
            files:'<path d="M1.5 7V5.5A1.5 1.5 0 0 1 3 4h5l3 2h10a1.5 1.5 0 0 1 1.5 1.5v12A1.5 1.5 0 0 1 21 21H3a1.5 1.5 0 0 1-1.5-1.5Z"/><path d="M4 9h16"/>',
            actions:'<path d="m12 2 9 6a2 2 0 0 1 0 3l-9 6-9-6a2 2 0 0 1 0-3Zm-8 12-1 1a2 2 0 0 0 0 3l9 6 9-6a2 2 0 0 0 0-3l-1-1"/>',
            clipboard:'<path d="M10 3V1h7l5 5v13h-6M17 1v6h5M3 7h7l6 6v11H3Zm7 0v6h6"/>',
            back:'<path d="m15 5-7 7 7 7"/>',
            chevron:'<path d="m9 5 7 7-7 7"/>',
            settings:'<path d="M4 6h16M4 12h16M4 18h16"/><circle cx="8" cy="6" r="2" fill="#171719"/><circle cx="16" cy="12" r="2" fill="#171719"/><circle cx="10" cy="18" r="2" fill="#171719"/>',
            command:'<rect x="3" y="4" width="18" height="16" rx="3"/><path d="m7 9 3 3-3 3m6 0h4"/>'
        };
        return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 '+(kind==='search'?'24':'26')+'"><g transform="translate(0 '+(kind==='search'?0:1)+')" fill="none" stroke="'+ink+'" stroke-width="'+(kind==='search'?2:1.8)+'" stroke-linecap="round" stroke-linejoin="round">'+(paths[kind]||paths.command)+'</g></svg>';
    }
}
