(* monadic parser combinators *)


(* parameterize over RE --------------------------------------------- *)

(* we want to parameterize over the re implementation *)

module type RE = sig
  type re

  val literal: string -> re

(*  val regexp: string -> re *)

  (* match regexp from offset off in s; return offset after match *)
  val string_match: re:re -> off:int -> string -> int option

  (* search forward from off to find offset where re matches *)
  val search_forward: re:re -> off:int -> string -> int option
end


module Str_ = struct
  type re = Str.regexp

  let literal s = Str.regexp_string s

(*  let regexp s = Str.regexp s *)

  let string_match ~re ~off s = 
    if (Str.string_match re s off) 
    then Some(Str.match_end ())  (* FIXME return all results? *)
    else None

  let search_forward ~re ~off s =
    try 
      Str.search_forward re s off |> fun k ->
      Some k
    with Not_found -> None    
end


module X_ = (Str_ : RE)


(* Make(Re) --------------------------------------------------------- *)
module Make(Re:RE) = struct

  (* worth working with indexes rather than strings? *)

  (* following extracted from tjr_lib to make this self-contained;
     primed so that no clash with original modules *)
  module P0_internal = struct
    module Tjr_substring = struct

      module String_position = struct
        type string_position = {
          s_:string;
          i_:int
        }
      end
      open String_position


      let re ~re s = 
        match (Re.string_match ~re ~off:s.i_ s.s_) with
        | None -> []
        | Some i -> [i]  (* FIXME return all results? *)


      let upto_re ~re s =
        Re.search_forward ~re ~off:s.i_ s.s_ |> function
        | None -> []
        | Some k -> [k]
    end



    module Tjr_string = struct
      let starts_with ~prefix b =
        let len = String.length prefix in
        len > String.length b |> function 
        | true -> false
        | false -> 
          let rec f j = 
            if j >= len then true else
              prefix.[j] = b.[j] &&
              f (j+1)
          in
          f 0

      (* more efficient version? *)
      let drop n s =
        String.length s |> fun l ->
        if n >= l then "" else
          String.sub s n (l-n)

      let split_at s n = (String.sub s 0 n, String.sub s n (String.length s - n))

    end
  end

  open P0_internal
  open Tjr_string

  let upto_a lit = Tjr_substring.upto_re ~re:Re.(literal lit)

  (* naive monadic parsing -------------------------------------------- *)

  (* experiment with monadic parsing; 'a m takes a string and returns an
     'a * string or an error/noparse indication *)

  type 'a m = string -> ('a * string) option

  let bind (f:'a -> 'b m) (x:'a m) :'b m = 
    fun s -> x s |> function | None -> None | Some (v,s) -> f v s
  let ( |>> ) x f = x |> bind f

  let return x s = Some(x,s)

  let then_ a b = a |>> fun x -> b |>> fun y -> return (x,y)
  let ( -- ) = then_

  (* FIXME improve this by using the result of the parse subsequently *)
  (* let can x s = Some (x s <> None,s) *)

  let a lit s = 
    if starts_with ~prefix:lit s 
    then drop (String.length lit) s |> fun s' -> Some(lit,s') 
    else None

  let upto_a lit = ( 
    let p = upto_a lit in
    fun s -> 
      p {s_=s;i_=0} |> fun xs ->
      if xs <> [] 
      then split_at s (List.hd xs) |> fun (s1,s2) -> Some(s1,s2)
      else None) [@@warning "-w-40"]

  let re re' = (
    fun s ->
      Tjr_substring.(re ~re:re' {s_=s;i_=0}) |> fun xs ->
      if xs <> []
      then split_at s (List.hd xs) |> fun (s1,s2) -> Some(s1,s2)
      else None) [@@warning "-w-40"]

  let upto_re re' = (
    fun s ->
      Tjr_substring.(upto_re ~re:re' {s_=s;i_=0}) |> fun xs ->
      if xs <> []
      then split_at s (List.hd xs) |> fun (s1,s2) -> Some(s1,s2)
      else 
        (* not found anywhere, so consume the whole string *)
        Some(s,"")) [@@warning "-w-40"]


  let opt p s = 
    p s |> function
    | None -> Some(None,s) 
    | Some(x,s) -> Some(Some x,s)

  let rec plus ~sep p = 
    p |>> fun x ->
    (opt (sep -- plus ~sep p)) |>> function
    | None -> return [x]
    | Some (_,xs) -> return (x::xs)

(*
let save s = Some(s,s)

(* jump back in time *)
let restore s' s = Some((),s')
*)

  let star ~sep p =
    opt p |>> function
    | None -> return []
    | Some x -> 
      opt (sep -- plus ~sep p) |>> function
      | None -> return [x]
      | Some (_,xs) -> return (x::xs)

  (* shortcut alternative *)
  let alt a b = 
    opt a |>> function
    | None -> b
    | Some x -> return x

  let ( || ) = alt       

  let discard p = p |>> fun _ -> return ()

  let ( --- ) a b = discard (a -- b) 

  let _Some x = Some x

  (* to avoid dependence on associativity of -- *)
  let _3 ((x1,x2),x3) = (x1,x2,x3)

end


(* Make(Str_) and include ------------------------------------------- *)
module P0_str = Make(Str_)

include P0_str