#!/usr/bin/env python3
"""Apply fixed continuous corners once; native apps never follow the Dock slider."""
import argparse
import json
import math
import os
from pathlib import Path
import re
import shutil
import subprocess
import xml.etree.ElementTree as ET


def number(value):
    return format(float(value), ".6f").rstrip("0").rstrip(".") or "0"


def quarter(cx, cy, rx, ry, start, finish, exponent, segments=40):
    points=[]
    for index in range(1,segments+1):
        angle=start+(finish-start)*index/segments
        co,si=math.cos(angle),math.sin(angle)
        points.append((cx+rx*math.copysign(abs(co)**(2/exponent),co),
                       cy+ry*math.copysign(abs(si)**(2/exponent),si)))
    return points


def contour(x,y,width,height,rx,ry,exponent):
    rx,ry=max(0,min(rx,width/2)),max(0,min(ry,height/2))
    if rx<=0 or ry<=0:
        return f"M{number(x)},{number(y)}h{number(width)}v{number(height)}h-{number(width)}Z"
    corners=((x+width-rx,y+ry,-math.pi/2,0),
             (x+width-rx,y+height-ry,0,math.pi/2),
             (x+rx,y+height-ry,math.pi/2,math.pi),
             (x+rx,y+ry,math.pi,3*math.pi/2))
    out=f"M{number(x+width-rx)},{number(y)}"
    for cx,cy,start,finish in corners:
        out+=f"L{number(cx+rx*math.cos(start))},{number(cy+ry*math.sin(start))}"
        out+="".join(f"L{number(px)},{number(py)}" for px,py in quarter(cx,cy,rx,ry,start,finish,exponent))
    return out+"Z"


def cubic_corner(start,c1,c2,end,exponent):
    x,y=start;ex,ey=end;dx,dy=ex-x,ey-y
    if min(abs(dx),abs(dy))<0.05:return None
    epsilon=max(abs(dx),abs(dy))*0.002
    horizontal=abs(c1[1]-y)<epsilon and abs(c2[0]-ex)<epsilon
    vertical=abs(c1[0]-x)<epsilon and abs(c2[1]-ey)<epsilon
    if horizontal:
        ratios=((c1[0]-x)/dx,(ey-c2[1])/dy)
        center=(x,ey)
    elif vertical:
        ratios=((c1[1]-y)/dy,(ex-c2[0])/dx)
        center=(ex,y)
    else:return None
    # A canonical quarter-circle/superellipse corner, not a freehand icon curve.
    if not all(0.45<=ratio<=0.70 for ratio in ratios):return None
    cx,cy=center
    start_angle=math.atan2((y-cy)/abs(dy),(x-cx)/abs(dx))
    end_angle=math.atan2((ey-cy)/abs(dy),(ex-cx)/abs(dx))
    delta=(end_angle-start_angle+math.pi)%(2*math.pi)-math.pi
    return quarter(cx,cy,abs(dx),abs(dy),start_angle,start_angle+delta,exponent)


TOKEN=re.compile(r"[a-zA-Z]|[-+]?(?:\d*\.\d+|\d+\.?\d*)(?:[eE][-+]?\d+)?")
ARITY={"M":2,"L":2,"H":1,"V":1,"C":6,"S":4,"Q":4,"T":2,"A":7}


def path_corners(data,exponent):
    """Replace canonical cubic rounded corners; retain other SVG geometry."""
    tokens=TOKEN.findall(data)
    out=[];i=0;command=None;x=y=0;origin=(0,0);previous="";last_c=last_q=None;changed=0
    try:
        while i<len(tokens):
            if tokens[i].isalpha():command=tokens[i];i+=1
            if command is None:raise ValueError("missing path command")
            upper=command.upper();relative=command.islower()
            if upper=="Z":
                out.append("Z");x,y=origin;previous="Z";last_c=last_q=None;command=None;continue
            count=ARITY[upper]
            values=list(map(float,tokens[i:i+count]));i+=count
            if len(values)!=count:raise ValueError("short path command")
            def at(px,py):return (px+x,py+y) if relative else (px,py)
            if upper in ("M","L"):
                end=at(*values);out.append(upper+",".join(map(number,end)))
                if upper=="M":origin=end;command="l" if relative else "L"
            elif upper in ("H","V"):
                end=((x+values[0] if relative else values[0]),y) if upper=="H" else (x,(y+values[0] if relative else values[0]))
                out.append("L"+",".join(map(number,end)))
            elif upper in ("C","S"):
                if upper=="C":c1=at(*values[:2]);c2=at(*values[2:4]);end=at(*values[4:])
                else:
                    c1=(2*x-last_c[0],2*y-last_c[1]) if previous in ("C","S") and last_c else (x,y)
                    c2=at(*values[:2]);end=at(*values[2:])
                points=cubic_corner((x,y),c1,c2,end,exponent)
                if points:
                    out.extend("L"+",".join(map(number,point)) for point in points);changed+=1
                else:out.append("C"+",".join(map(number,(*c1,*c2,*end))))
                last_c=c2
            elif upper in ("Q","T"):
                if upper=="Q":control=at(*values[:2]);end=at(*values[2:])
                else:
                    control=(2*x-last_q[0],2*y-last_q[1]) if previous in ("Q","T") and last_q else (x,y)
                    end=at(*values)
                out.append("Q"+",".join(map(number,(*control,*end))));last_q=control
            else:
                end=at(*values[-2:]);out.append("A"+",".join(map(number,(*values[:-2],*end))))
            x,y=end;previous=upper
        return (" ".join(out),changed) if changed else (data,0)
    except (ValueError,KeyError,IndexError,OverflowError):return data,0


def convert_svg(source,exponent):
    for _,namespace in ET.iterparse(source,events=["start-ns"]):
        prefix,uri=namespace
        if not re.fullmatch(r"ns\d+",prefix):ET.register_namespace(prefix,uri)
    tree=ET.parse(source);count=0
    # Native application controls keep their original artwork, including radio
    # discs and slider handles. Only surrounding surfaces share the panel curve.
    controls=re.compile(r"^(?:(?:expand-)?(?:button|tbutton|combo|slider|slidercursor|scrollbar|scrollbarslider|scrollbargroove|spin|tab|tab-close|dial|lineedit|tlineedit)|(?:menu-|item-)?(?:checkbox|radio)|menubaritem|menuitem)(?:-|$)")
    protected=set()
    identifiers={element.get("id"):element for element in tree.getroot().iter() if element.get("id")}
    for element in tree.getroot().iter():
        if controls.match(element.get("id","")):
            protected.update(element.iter())
    pending=list(protected)
    while pending:
        element=pending.pop()
        for key in ("href","{http://www.w3.org/1999/xlink}href"):
            reference=element.get(key,"")
            if reference.startswith("#") and reference[1:] in identifiers:
                for target in identifiers[reference[1:]].iter():
                    if target not in protected:
                        protected.add(target);pending.append(target)
    for element in tree.getroot().iter():
        if element in protected:continue
        tag=element.tag.rsplit("}",1)[-1]
        try:
            if tag=="rect":
                rx=float(element.get("rx",element.get("ry","0")));ry=float(element.get("ry",str(rx)))
                if rx<=0 or ry<=0:continue
                data=contour(float(element.get("x","0")),float(element.get("y","0")),float(element.get("width","0")),float(element.get("height","0")),rx,ry,exponent)
                remove=("x","y","width","height","rx","ry")
            elif tag in ("circle","ellipse"):
                rx=float(element.get("r",element.get("rx","0")));ry=float(element.get("r",element.get("ry","0")))
                cx,cy=float(element.get("cx","0")),float(element.get("cy","0"))
                data=contour(cx-rx,cy-ry,2*rx,2*ry,rx,ry,exponent);remove=("cx","cy","r","rx","ry")
            elif tag=="path":
                data,converted=path_corners(element.get("d",""),exponent)
                if converted:element.set("d",data);count+=converted
                continue
            else:continue
            element.tag=element.tag.replace(tag,"path")
            for attribute in remove:element.attrib.pop(attribute,None)
            element.set("d",data);count+=1
        except (ValueError,OverflowError):continue
    return ET.tostring(tree.getroot(),encoding="utf-8",xml_declaration=True),count


def write_changed(path,content):
    path=Path(path);content=content.encode() if isinstance(content,str) else content
    if path.exists() and path.read_bytes()==content:return False
    path.parent.mkdir(parents=True,exist_ok=True)
    temporary=path.with_name(path.name+".corners-tmp")
    temporary.write_bytes(content);os.replace(temporary,path)
    return True


def baseline(root,path):
    saved=root/".local/share/macshell/corners/base"/path.relative_to(root)
    if not saved.exists():saved.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(path,saved)
    return saved


def asset(exponent,radius,top,bottom=None,stroke="#00000000",tick=False):
    def svg_color(value):
        if re.fullmatch(r"#[0-9a-fA-F]{8}",value):
            return value[:7],int(value[7:9],16)/255
        return value,1
    bottom=bottom or top
    top,top_alpha=svg_color(top);bottom,bottom_alpha=svg_color(bottom)
    stroke,stroke_alpha=svg_color(stroke)
    outline=contour(0.5,0.5,95,63,radius-0.5,radius-0.5,exponent)
    overlay='<path d="M35 32l9 9 19-21" fill="none" stroke="white" stroke-width="6" stroke-linecap="round" stroke-linejoin="round"/>' if tick else ""
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="96" height="64" viewBox="0 0 96 64">'
        '<defs><linearGradient id="fill" x2="0" y2="1"><stop stop-color="'+top+'" stop-opacity="'+number(top_alpha)+'"/><stop offset="1" stop-color="'+bottom+'" stop-opacity="'+number(bottom_alpha)+'"/></linearGradient></defs>'
        '<path d="'+outline+'" fill="url(#fill)" stroke="'+stroke+'" stroke-opacity="'+number(stroke_alpha)+'"/>'+overlay+'</svg>')


def gtk_overrides(directory,dark):
    def url(name):return (directory/(name+".svg")).as_uri()
    def frame(name,radius):return f'background-color:transparent; background-image:none; border:1px solid transparent; border-radius:0; box-shadow:none; border-image-source:url("{url(name)}"); border-image-slice:{radius} fill; border-image-width:{radius}px; border-image-repeat:stretch;'
    return '''\n/* MacShell continuous corners: generated Lamé SVG frames. */\n'''+"\n".join([
        'window.background, window.csd, decoration, headerbar, .titlebar { border-radius:0; }',
        'popover > contents, popover.background, menu, .menu, .card, frame > border { '+frame("panel",24)+' }'
    ])+'\n'


def gtk_with_nautilus_theme(root,path,source):
    """Keep MacTahoe's native GTK4 geometry instead of generated corner frames."""
    if path.parent.name != "gtk-4.0":return source
    integration=root/".config/macshell/nautilus"
    theme=integration/"theme-import.css"
    compatibility=integration/"compat.css"
    if not theme.is_file():return source
    source=re.sub(r'\n?/\* MacShell continuous corners: generated Lamé SVG frames\. \*/\n[^\n]*\n[^\n]*\n?', '', source)
    result='@import url("'+theme.as_uri()+'");\n'+source
    if compatibility.is_file():result+='\n@import url("'+compatibility.as_uri()+'");\n'
    return result


def restore_round(root,ipc=True):
    """Restore original native themes and keep circular window corners.

    Zero smoothing restores the exact original native theme files.
    """
    generated=root/".config/macshell/corners"
    themes=0
    for path in sorted((root/".config/Kvantum").glob("*/*.svg")):
        write_changed(path,baseline(root,path).read_bytes());themes+=1
    for relative in (".config/gtk-3.0/gtk.css", ".config/gtk-4.0/gtk.css",
                     ".config/macshell/dolphin/sidebar.qss"):
        path=root/relative
        if path.exists():write_changed(path,gtk_with_nautilus_theme(root,path,baseline(root,path).read_text()))
    write_changed(generated/"hypr.lua","-- Classic circular window corners.\nreturn { power = 2 }\n")
    if ipc:
        try:
            result=subprocess.run(["hyprctl","keyword","decoration:rounding_power","2"],capture_output=True,text=True,timeout=5)
            if result.returncode:print(json.dumps({"warning":result.stderr.strip() or result.stdout.strip()}),flush=True)
        except (OSError,subprocess.SubprocessError) as error:print(json.dumps({"warning":str(error)}),flush=True)
    result={"amount":0,"exponent":2,"themes":themes,"curves":0}
    write_changed(generated/"state.json",json.dumps(result))
    return result


def apply_defaults(root,ipc=True):
    amount=0.35
    exponent=2+2*amount;generated=root/".config/macshell/corners"
    total=0;themes=0
    for path in sorted((root/".config/Kvantum").glob("*/*.svg")):
        source=baseline(root,path);data,count=convert_svg(source,exponent)
        write_changed(path,data);total+=count;themes+=1
    # GTK panels follow the slider; control frames keep circular corners.
    for dark in (False,True):
        directory=generated/("dark" if dark else "light")
        palette={
            "control":("#414148","#34343A","#606068"),
            "hover":("#55555F","#484851","#777780"),
            "panel":("#303036","#25252A","#505059"),
            "knob":("#F5F5F8","#DADAE0","#FFFFFF")
        } if dark else {
            "control":("#FFFFFF","#ECECF0","#C5C5CE"),
            "hover":("#ECECF2","#DEDEE8","#B9B9C4"),
            "panel":("#F8F8FA","#ECECF0","#C9C9D1"),
            "knob":("#FFFFFF","#EEEEF3","#BDBDC7")
        }
        palette["accent"]=("#3989F4","#2473DB","#60A3FA")
        palette["checked"]=palette["accent"]
        for name,(top,bottom,stroke) in palette.items():
            write_changed(directory/(name+".svg"),asset(exponent if name=="panel" else 2,24 if name=="panel" else 10,top,bottom,stroke,tick=name=="checked"))
    for version in ("gtk-3.0","gtk-4.0"):
        directory=root/".config"/version
        settings=(directory/"settings.ini").read_text() if (directory/"settings.ini").exists() else ""
        dark="-Dark" in settings or "prefer-dark-theme=1" in settings
        target=directory/"gtk.css"
        if target.exists():source=baseline(root,target).read_text()
        else:source="";write_changed(target,source);baseline(root,target)
        write_changed(target,gtk_with_nautilus_theme(root,target,source+gtk_overrides(generated/("dark" if dark else "light"),dark)))
    # Keep the existing Finder-style Dolphin panel gradient and spacing.
    qss=root/".config/macshell/dolphin/sidebar.qss"
    if qss.exists():
        source=baseline(root,qss).read_text()
        panel=generated/"dolphin-panel.svg";selection=generated/"dolphin-selection.svg";hover=generated/"dolphin-hover.svg"
        write_changed(panel,asset(exponent,24,"#34304e","#242b42","#c5bdf426"))
        write_changed(selection,asset(exponent,6,"#504969"))
        write_changed(hover,asset(exponent,6,"#d0c7ff12"))
        # QSS border-image uses local paths rather than file URLs.
        def border(path,slice):return f'background:transparent; border:0; border-radius:0; border-image:url("{path}") {slice} {slice} {slice} {slice} stretch stretch;'
        source+='\n/* Shared Continuous Corner setting. */\n'
        source+='QDockWidget#placesDock PlacesPanel { '+border(panel,24)+' }\n'
        source+='QDockWidget#placesDock PlacesPanel::item:selected { '+border(selection,6)+' }\n'
        source+='QDockWidget#placesDock PlacesPanel::item:hover:!selected { '+border(hover,6)+' }\n'
        write_changed(qss,source)
    write_changed(generated/"hypr.lua","-- Generated from the shared Continuous Corner slider.\nreturn { power = "+number(exponent)+" }\n")
    if ipc:
        try:
            result=subprocess.run(["hyprctl","keyword","decoration:rounding_power",number(exponent)],capture_output=True,text=True,timeout=5)
            if result.returncode:print(json.dumps({"warning":result.stderr.strip() or result.stdout.strip()}),flush=True)
        except (OSError,subprocess.SubprocessError) as error:print(json.dumps({"warning":str(error)}),flush=True)
    result={"amount":amount,"exponent":exponent,"themes":themes,"curves":total}
    write_changed(generated/"state.json",json.dumps(result))
    return result


def synchronize(root,amount=0,ipc=True):
    """Dock slider values never change the fixed native UI default."""
    return apply_defaults(root,ipc)


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("--root",type=Path,default=Path.home())
    parser.add_argument("--once",action="store_true")
    parser.add_argument("--no-ipc",action="store_true")
    args=parser.parse_args()
    try:
        print(json.dumps(apply_defaults(args.root,not args.no_ipc)),flush=True)
    except (OSError,ValueError,TypeError) as error:
        print(json.dumps({"warning":str(error)}),flush=True)



if __name__=="__main__":main()
