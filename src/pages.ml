open Printf
open Cohttp
open Lwt
open Cow

let read_file tmpl_read f =
  try_lwt
  let suffix =
    try let n = String.rindex f '.' in
        String.sub f (n+1) (String.length f - n - 1)
    with _ -> "" in
  match suffix with
    | "md"   -> tmpl_read f >|= Markdown.of_string
    | "html" -> tmpl_read f >|= Html.of_string
    | _      -> return []
  with exn ->
    printf "Pages.read_file: exception %s\n%!" (Printexc.to_string exn);
    exit 1

let two_cols l r = <:html<
  <div class="row">
    <div class="large-6 columns">$l$</div>
    <div class="large-6 columns">$r$</div>
  </div>
>>

module Global = struct
   let nav_links = [
    "Blog", Uri.of_string "/blog";
    "Docs", Uri.of_string "/docs";
    "API", Uri.of_string "http://mirage.github.io";  (* TODO integrate *)
    "Community", Uri.of_string "/community";
  ]

  let top_nav =
    Cowabloga.Foundation.top_nav
      ~title:<:html<<img src="/graphics/mirage-logo-small.png" />&>>
      ~title_uri:(Uri.of_string "/")
      ~nav_links:(Cowabloga.Foundation.Link.top_nav ~align:`Left nav_links)

  let page ~title ~headers ~content =
    let font = <:html<
      <link rel="stylesheet" href="/css/foundation-icons.css"> </link>
      <link href="http://fonts.googleapis.com/css?family=Source+Sans+Pro:400,600,700" rel="stylesheet" type="text/css"> </link>
    >> in
    let headers = font @ headers in
    let content = top_nav @ content in
    let body = Cowabloga.Foundation.body ~title ~headers ~content in
    Cowabloga.Foundation.page ~body
end

module Index = struct
  let t read_fn =
    lwt l1 = read_file read_fn "/intro-1.md" in
    lwt l2 = read_file read_fn "/intro-3.md" in
    lwt footer = read_file read_fn "/intro-f.html" in
    let content = <:xml<
    <div class="row">
      <div class="small-12 columns">
        <h3>A programming framework for building type-safe, modular systems</h3>
      </div>
    </div>
    <div class="row">
      <div class="small-12 medium-6 columns">$l1$</div>
      <div class="small-12 medium-6 columns">$l2$</div>
    </div>
    <div class="row">
      <div class="small-12 columns">$footer$</div>
    </div>
    >> in
    return (Global.page ~title:"Mirage OS" ~headers:[] ~content)
end

module About = struct

  let t read_fn =
    lwt i = read_file read_fn "/about-intro.md" in
    lwt l = read_file read_fn "/about.md" in
    lwt r = read_file read_fn "/about-community.md" in
    lwt b = read_file read_fn "/about-b.md" in
    lwt f = read_file read_fn "/about-funding.md" in
    let content = <:html<
    <div class="row">
      <div class="small-12 medium-6 columns">$i$</div>
      <div class="small-12 medium-6 columns">$f$</div>
    </div>
    <div class="row">
      <div class="small-12 columns">$b$</div>
    </div>
    <div class="row">
      <div class="small-12 medium-6 columns">$l$</div>
      <div class="small-12 medium-6 columns">$r$</div>
    </div>
    >> in
    return (Global.page ~title:"Community" ~headers:[] ~content)
end

module Wiki = struct
  open Cowabloga.Wiki
  open Data.Wiki
  open Wiki

  let read_file read_fn f = read_file read_fn ("/wiki/" ^ f)

  (* Make a full Html.t including RSS link and headers from an wiki page *)
  let make ?title ?disqus content sidebar read_fn =
    let url = sprintf "/wiki/atom.xml" in
    let headers = <:xml<
     <link rel="alternate" type="application/atom+xml" href=$str:url$ />
    >> in
    let title = "wiki" ^ match title with
      |None -> "" |Some x -> " :: " ^ x in
    lwt content = html_of_page ?disqus ~content ~sidebar in
    return (Global.page ~title:"Documentation" ~headers ~content)

  (* Main wiki page Html.t fragment with the index page *)
  let main_page read_fn =
    lwt idx = html_of_index (read_file read_fn) in
    let sidebar = html_of_recent_updates Wiki.entries in
    make ~title:"index"  (return idx) sidebar read_fn

  let init read_fn =
    let ent_bodies = Hashtbl.create 1 in
    List.iter (fun entry ->
      let title = entry.subject in
      let left = html_of_entry (read_file read_fn) entry in
      let body = make ~title ~disqus:entry.permalink left [] read_fn in
      Hashtbl.add ent_bodies entry.permalink body
    ) entries;
    ent_bodies

  let atom_feed read_fn =
    lwt f = atom_feed (read_file read_fn) entries in
    return (Xml.to_string (Atom.xml_of_feed ~self:("/wiki/atom.xml") f))

  let not_found x ent_bodies read_fn =
    let left =
      sprintf "Not found: %s (known links: wiki/%s)"
        (String.concat " ... " x)
        (String.concat " "
           (Hashtbl.fold (fun k v a -> k :: a)
              ent_bodies [])) in
    make ~title:"Not Found" (return <:xml<$str:left$>>) [] read_fn

  let content_type_xhtml = ["content-type", "text/html"]
  let t ents read_fn = function
    | []                          -> content_type_xhtml, (main_page read_fn)
    | ["atom.xml"]                -> ["content-type","application/atom+xml; charset=UTF-8"], (atom_feed read_fn)
    | [x] when permalink_exists x -> content_type_xhtml, (Hashtbl.find ents x)
    | x                           -> content_type_xhtml, (not_found x ents read_fn)

end
