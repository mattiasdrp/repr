open Crowbar

(* TODO(liautaud): Add support for variants and enums. *)
(* FIXME(liautaud): new_dynrec_getter breaks with nested type parameters. *)

module T = Irmin.Type

let ( |+ ) = T.( |+ )

let ( |~ ) = T.( |~ )

let fmt = Format.sprintf

(* This is part of the standard library as of 4.08 (see [Option.map]). *)
let option_map f o = match o with None -> None | Some t -> Some (f t)

(* This is part of the standard library as of 4.08 (see [Result.map] and [Result.map_error]). *)
let result_map fa fe r =
  match r with Ok a -> Ok (fa a) | Error e -> Error (fe e)

(* This has to be upstreamed to Crowbar. In the meantime, you can run:
   {v opam pin crowbar https://github.com/stedolan/crowbar.git#master v}. *)
let char = map [ bytes_fixed 1 ] (fun s -> s.[0])

let string = bytes

let bytes = map [ string ] Bytes.of_string

let triple a b c = map [ a; b; c ] (fun a b c -> (a, b, c))

(* Untyped internal representation of Irmin values. *)
type any_value =
  | VUnit of unit
  | VBool of bool
  | VChar of char
  | VInt of int
  | VInt32 of int32
  | VInt64 of int64
  | VFloat of float
  | VString of string
  | VBytes of bytes
  | VList of any_value list
  | VArray of any_value array
  | VOption of any_value option
  | VPair of any_value * any_value
  | VTriple of any_value * any_value * any_value
  | VResult of (any_value, any_value) result
  | VRecord of dyn_record
[@@deriving show]

(* Since we can't use "real" records and variants to test how Irmin serializes
   and deserializes them, we instead represent records with a hashtable of all
   their fields, and variants as the name of the current constructor and its value. *)
and dyn_record = (string * (string, any_value) Hashtbl.t[@opaque])

(** Internal representation of Irmin types. *)
type 'a t =
  | TUnit : unit t
  | TBool : bool t
  | TChar : char t
  | TInt : int t
  | TInt32 : int32 t
  | TInt64 : int64 t
  | TFloat : float t
  | TString : string t
  | TBytes : bytes t
  | TList : 'a t -> 'a list t
  | TArray : 'a t -> 'a array t
  | TOption : 'a t -> 'a option t
  | TPair : 'a t * 'b t -> ('a * 'b) t
  | TTriple : 'a t * 'b t * 'c t -> ('a * 'b * 'c) t
  | TResult : 'a t * 'e t -> ('a, 'e) result t
  (* Each of these lists must have 1 to 4 elements. *)
  | TRecord : string * field list -> dyn_record t

(* | TVariant : string * case list -> dyn_variant t
   | TEnum : string * string list -> dyn_variant t *)

(* Allows heterogeneous types to be handled together. *)
and any_type = AT : 'a t -> any_type

and field = string * any_type

(** Pretty-print an [any_type] value. This should be generated by ppx_deriving,
    but it doesn't support GADTs. *)
let rec show_any_type = function
  | AT TUnit -> "TUnit"
  | AT TBool -> "TBool"
  | AT TChar -> "TChar"
  | AT TInt -> "TInt"
  | AT TInt32 -> "TInt32"
  | AT TInt64 -> "TInt64"
  | AT TFloat -> "TFloat"
  | AT TString -> "TString"
  | AT TBytes -> "TBytes"
  | AT (TList t) -> fmt "TList (%s)" (show_any_type (AT t))
  | AT (TArray t) -> fmt "TArray (%s)" (show_any_type (AT t))
  | AT (TOption t) -> fmt "TOption (%s)" (show_any_type (AT t))
  | AT (TPair (ta, tb)) ->
      fmt "TPair (%s, %s)" (show_any_type (AT ta)) (show_any_type (AT tb))
  | AT (TTriple (ta, tb, tc)) ->
      fmt "TTriple (%s, %s, %s)" (show_any_type (AT ta)) (show_any_type (AT tb))
        (show_any_type (AT tc))
  | AT (TResult (ta, te)) ->
      fmt "TResult (%s, %s)" (show_any_type (AT ta)) (show_any_type (AT te))
  | AT (TRecord (name, fields)) ->
      let show_field (n, t) = fmt "(%s, %s)" n (show_any_type t) in
      let fields_fmt = String.concat "; " (List.map show_field fields) in
      fmt "TRecord (%s, [%s])" name fields_fmt

(* and case = string * any_case_type
and 'a case_type =
  | Case0 : dyn_variant case_type
  | Case1 : ('a t) -> ('a -> dyn_variant) case_type *)

(* and dyn_variant = string * any_value *)
(* and any_case_type = ACT : 'a case_type -> any_case_type *)

(** Wrap a value of the given dynamic type into an [any_value]. *)
let rec wrap : type a. a t -> a -> any_value =
 fun t v ->
  match t with
  | TUnit -> VUnit v
  | TBool -> VBool v
  | TChar -> VChar v
  | TInt -> VInt v
  | TInt32 -> VInt32 v
  | TInt64 -> VInt64 v
  | TFloat -> VFloat v
  | TString -> VString v
  | TBytes -> VBytes v
  | TList t' -> VList (List.map (wrap t') v)
  | TArray t' -> VArray (Array.map (wrap t') v)
  | TOption t' -> VOption (option_map (wrap t') v)
  | TPair (t1, t2) ->
      let v1, v2 = v in
      VPair (wrap t1 v1, wrap t2 v2)
  | TTriple (t1, t2, t3) ->
      let v1, v2, v3 = v in
      VTriple (wrap t1 v1, wrap t2 v2, wrap t3 v3)
  | TResult (ta, te) -> VResult (result_map (wrap ta) (wrap te) v)
  | TRecord _ -> VRecord v

(** Unwrap an [any_value] of the given dynamic type. *)
let rec unwrap : type a. a t -> any_value -> a =
 fun t w ->
  match (t, w) with
  | TUnit, VUnit v -> v
  | TBool, VBool v -> v
  | TChar, VChar v -> v
  | TInt, VInt v -> v
  | TInt32, VInt32 v -> v
  | TInt64, VInt64 v -> v
  | TFloat, VFloat v -> v
  | TString, VString v -> v
  | TBytes, VBytes v -> v
  | TList t', VList v -> List.map (unwrap t') v
  | TArray t', VArray v -> Array.map (unwrap t') v
  | TOption t', VOption v -> option_map (unwrap t') v
  | TPair (t1, t2), VPair (v1, v2) -> (unwrap t1 v1, unwrap t2 v2)
  | TTriple (t1, t2, t3), VTriple (v1, v2, v3) ->
      (unwrap t1 v1, unwrap t2 v2, unwrap t3 v3)
  | TResult (ta, te), VResult v -> result_map (unwrap ta) (unwrap te) v
  | TRecord _, VRecord v -> v
  | _ ->
      failwith
      @@ fmt "Tried to unwrap %s while expecting type %s." (show_any_value w)
           (show_any_type (AT t))

(** Generate a variable-length list of unique elements.

    - [~min] is the minimum length of the generated list (defaults to 0).
    - [~max] is the maximum length of the generated list (defaults to +inf).
    - [~cmp] is the comparison function (defaults to the polymorphic compare). *)
let unique_list (type a) ?(min = 0) ?(max = max_int) ?(cmp = compare)
    (gen : a gen) =
  let module S = Set.Make (struct
    type t = a

    let compare = cmp
  end) in
  let rec aux set =
    let n = S.cardinal set in
    if n < min then dynamic_bind gen (fun x -> aux (S.add x set))
    else if n >= max then const (S.elements set)
    else
      choose
        [
          const (S.elements set); dynamic_bind gen (fun x -> aux (S.add x set));
        ]
  in
  aux S.empty

(** Generate a dynamic type recursively. *)
let t_gen =
  fix (fun t_gen ->
      let field_gen = pair string t_gen in
      let fields_gen =
        unique_list ~min:1
          ~max:4 (* Make sure that each case has a different name. *)
          ~cmp:(fun (s1, _) (s2, _) -> String.compare s1 s2)
          field_gen
      in
      (* let case_gen = pair string (choose
           [
             const (ACT Case0);
             map [t_gen] (fun t -> ACT (Case1 t));
           ])
         in *)
      choose
        [
          const (AT TUnit);
          const (AT TBool);
          const (AT TChar);
          const (AT TInt);
          const (AT TInt32);
          const (AT TInt64);
          const (AT TFloat);
          const (AT TString);
          const (AT TBytes);
          map [ t_gen ] (fun (AT t) -> AT (TList t));
          map [ t_gen ] (fun (AT t) -> AT (TArray t));
          map [ t_gen ] (fun (AT t) -> AT (TOption t));
          map [ t_gen; t_gen ] (fun (AT t1) (AT t2) -> AT (TPair (t1, t2)));
          map [ t_gen; t_gen; t_gen ] (fun (AT t1) (AT t2) (AT t3) ->
              AT (TTriple (t1, t2, t3)));
          map [ t_gen; t_gen ] (fun (AT t1) (AT t2) -> AT (TResult (t1, t2)));
          map [ string; fields_gen ] (fun s fs -> AT (TRecord (s, fs)));
          (* map [string; one_up_to 4 case_gen] (fun s cs -> AT (TVariant (s, cs)));
             map [string; one_up_to 4 string] (fun s ts -> AT (TEnum (s, ts))); *)
        ])

(** Convert a [t] into its [Irmin.Type] counterpart. *)
let rec t_to_irmin : type a. a t -> a T.ty = function
  | TUnit -> T.unit
  | TBool -> T.bool
  | TChar -> T.char
  | TInt -> T.int
  | TInt32 -> T.int32
  | TInt64 -> T.int64
  | TFloat -> T.float
  | TString -> T.string
  | TBytes -> T.bytes
  | TList t -> T.list (t_to_irmin t)
  | TArray t -> T.array (t_to_irmin t)
  | TOption t -> T.option (t_to_irmin t)
  | TPair (t1, t2) -> T.pair (t_to_irmin t1) (t_to_irmin t2)
  | TTriple (t1, t2, t3) ->
      T.triple (t_to_irmin t1) (t_to_irmin t2) (t_to_irmin t3)
  | TResult (t1, t2) -> T.result (t_to_irmin t1) (t_to_irmin t2)
  | TRecord (s, fs) -> irmin_record s fs
  (* | Variant (s, cs) -> irmin_variant s cs
     | Enum (s, cs) -> irmin_enum s cs *)

(** Dynamically build an Irmin record (assuming it has 1 to 4 fields). *)
and irmin_record : string -> field list -> dyn_record T.t =
 fun name fields ->
  match fields with
  | [ (n, AT t) ] ->
      T.record name (fun v -> new_dynrec name [ (n, wrap t v) ])
      |+ T.field n (t_to_irmin t) (new_dynrec_getter name n t)
      |> T.sealr
  | [ (n1, AT t1); (n2, AT t2) ] ->
      T.record name (fun v1 v2 ->
          new_dynrec name [ (n1, wrap t1 v1); (n2, wrap t2 v2) ])
      |+ T.field n1 (t_to_irmin t1) (new_dynrec_getter name n1 t1)
      |+ T.field n2 (t_to_irmin t2) (new_dynrec_getter name n2 t2)
      |> T.sealr
  | [ (n1, AT t1); (n2, AT t2); (n3, AT t3) ] ->
      T.record name (fun v1 v2 v3 ->
          new_dynrec name
            [ (n1, wrap t1 v1); (n2, wrap t2 v2); (n3, wrap t3 v3) ])
      |+ T.field n1 (t_to_irmin t1) (new_dynrec_getter name n1 t1)
      |+ T.field n2 (t_to_irmin t2) (new_dynrec_getter name n2 t2)
      |+ T.field n3 (t_to_irmin t3) (new_dynrec_getter name n3 t3)
      |> T.sealr
  | [ (n1, AT t1); (n2, AT t2); (n3, AT t3); (n4, AT t4) ] ->
      T.record name (fun v1 v2 v3 v4 ->
          new_dynrec name
            [
              (n1, wrap t1 v1);
              (n2, wrap t2 v2);
              (n3, wrap t3 v3);
              (n4, wrap t4 v4);
            ])
      |+ T.field n1 (t_to_irmin t1) (new_dynrec_getter name n1 t1)
      |+ T.field n2 (t_to_irmin t2) (new_dynrec_getter name n2 t2)
      |+ T.field n3 (t_to_irmin t3) (new_dynrec_getter name n3 t3)
      |+ T.field n4 (t_to_irmin t4) (new_dynrec_getter name n4 t4)
      |> T.sealr
  | _ ->
      failwith "The given TRecord has a number of fields outside of [|1; 4|]."

(** Dynamically build an Irmin variant (assuming it has 1 to 4 fields). *)

(** Create a [dyn_record] from a list of [string * any_value] pairs. *)
(* and irmin_variant name = function
  | [(n, case)] ->
      T.variant name (fun c -> new_dynvar_matcher [(n, case, c)])
    |~ new_dynvar_case n case
    |> T.sealv
  | _ -> failwith "The given TVariant has a number of fields outside of [|1; 4|]."

and irmin_enum s cs = () *)
and new_dynrec : string -> (string * any_value) list -> dyn_record =
 fun name fields ->
  let record = Hashtbl.create (List.length fields) in
  List.iter (fun (k, v) -> Hashtbl.add record k v) fields;
  (name, record)

(** Create a function which retrieves a value of the given dynamic type from a
    [dyn_record] or fails. *)
and new_dynrec_getter : type a. string -> string -> a t -> dyn_record -> a =
 fun record_name field_name field_type dynrec ->
  let curr_record_name, curr_table = dynrec in
  if not (String.equal record_name curr_record_name) then
    failwith "Trying to access fields from the wrong record."
  else
    let wrapped = Hashtbl.find curr_table field_name in
    unwrap field_type wrapped

(** Create a function which acts as pattern matching for a dynamic variant. *)

(* and new_dynvar_matcher = *)
(* (string * case_type * 'a) list -> (dyn_variant -> 'a) *)
(* assert false *)

(** Create a [Irmin.Type.case] from the given case name and case type. *)

(* and new_dynvar_case : type a. string -> a case_type -> (dyn_variant, a T.case_p) T.case = fun n c -> match c with
  | Case0 -> T.case0 n (n, wrap TUnit ())
  | Case1 t -> T.case1 n (t_to_irmin t) (fun v -> (n, wrap t v)) *)

(** Create a generator for values of a given dynamic type. *)
let rec t_to_value_gen : type a. a t -> a gen = function
  | TUnit -> const ()
  | TBool -> bool
  | TChar -> char
  | TInt -> int
  | TInt32 -> int32
  | TInt64 -> int64
  | TFloat -> float
  | TString -> string
  | TBytes -> bytes
  | TList ty -> list (t_to_value_gen ty)
  | TArray ty -> map [ list (t_to_value_gen ty) ] Array.of_list
  | TOption ty -> option (t_to_value_gen ty)
  | TPair (ty1, ty2) -> pair (t_to_value_gen ty1) (t_to_value_gen ty2)
  | TTriple (ty1, ty2, ty3) ->
      triple (t_to_value_gen ty1) (t_to_value_gen ty2) (t_to_value_gen ty3)
  | TResult (ty1, ty2) -> result (t_to_value_gen ty1) (t_to_value_gen ty2)
  | TRecord (s, fs) -> irmin_record_gen s fs

(** Create a generator for an Irmin record with the given specification. *)
and irmin_record_gen : string -> field list -> dyn_record gen =
 fun name fields ->
  match fields with
  | [ (n, AT t) ] ->
      map [ t_to_value_gen t ] (fun v -> new_dynrec name [ (n, wrap t v) ])
  | [ (n1, AT t1); (n2, AT t2) ] ->
      map [ t_to_value_gen t1; t_to_value_gen t2 ] (fun v1 v2 ->
          new_dynrec name [ (n1, wrap t1 v1); (n2, wrap t2 v2) ])
  | [ (n1, AT t1); (n2, AT t2); (n3, AT t3) ] ->
      map [ t_to_value_gen t1; t_to_value_gen t2; t_to_value_gen t3 ]
        (fun v1 v2 v3 ->
          new_dynrec name
            [ (n1, wrap t1 v1); (n2, wrap t2 v2); (n3, wrap t3 v3) ])
  | [ (n1, AT t1); (n2, AT t2); (n3, AT t3); (n4, AT t4) ] ->
      map
        [
          t_to_value_gen t1;
          t_to_value_gen t2;
          t_to_value_gen t3;
          t_to_value_gen t4;
        ] (fun v1 v2 v3 v4 ->
          new_dynrec name
            [
              (n1, wrap t1 v1);
              (n2, wrap t2 v2);
              (n3, wrap t3 v3);
              (n4, wrap t4 v4);
            ])
  | _ ->
      failwith "The given TRecord has a number of fields outside of [|1; 4|]."

type inhabited = Inhabited : 'a T.t * 'a -> inhabited

(** Generate a [Inhabited (t, v)], where [t : 'a Irmin.Type.t] is a dynamic type
    and [v : 'a] is a corresponding value. *)
let inhabited_gen : inhabited gen =
  dynamic_bind t_gen @@ fun (AT t) ->
  map [ t_to_value_gen t ] (fun v -> Inhabited (t_to_irmin t, v))

<<<<<<< HEAD
let rec ty_to_value_gen : type a. a ty -> a gen = function
  | Unit -> const ()
  | Bool -> bool
  | Char -> char
  | Int -> int
  | Int32 -> int32
  | Int64 -> int64
  | Float -> float
  | String -> string
  (* | String_of _ -> string *)
  | Bytes -> bytes
  (* | Bytes_of _ -> bytes *)
  | List ty -> list (ty_to_value_gen ty)
  | Array ty -> map [ list (ty_to_value_gen ty) ] Array.of_list
  | Option ty -> option (ty_to_value_gen ty)
  | Pair (ty1, ty2) -> pair (ty_to_value_gen ty1) (ty_to_value_gen ty2)
  | Triple (ty1, ty2, ty3) ->
      triple (ty_to_value_gen ty1) (ty_to_value_gen ty2) (ty_to_value_gen ty3)
  | Result (ty1, ty2) -> result (ty_to_value_gen ty1) (ty_to_value_gen ty2)

type pair = Pair : 'a T.t * 'a -> pair

let pair_gen : pair gen =
  dynamic_bind ty_gen @@ fun (Any t) ->
  let itype_gen = ty_to_irmin_gen t in
  let val_gen = ty_to_value_gen t in
  map [ itype_gen; val_gen ] (fun t v -> Pair (t, v))

(** Check that the value [v], of dynamic type [t], stays consistent after
    encoding then decoding. *)
let inhabited_check (Inhabited (t, v)) =
  let encoded = T.(unstage (to_bin_string t)) v in
  match T.(unstage (of_bin_string t)) encoded with
  | Error _ -> failf "Could not deserialize %s." encoded
  | Ok v' -> check_eq v v'

let () =
  add_test ~name:"T.of_bin_string and T.to_bin_string are mutually inverse."
    [ inhabited_gen ] inhabited_check