{ mkDerivation, base, containers, dlist, exceptions, generic-lens
, hspec, hspec-jenkins, lens, monad-control, monad-unlift, mtl
, mutable-containers, primitive, safe-exceptions, silently, stdenv
, streaming, temporary, text, transformers, unliftio, unliftio-core
}:
mkDerivation {
  pname = "capabilities-via";
  version = "0.1.0.0";
  src = ../../..;
  libraryHaskellDepends = [
    base dlist exceptions generic-lens lens monad-control monad-unlift
    mtl mutable-containers primitive safe-exceptions streaming
    transformers unliftio unliftio-core
  ];
  testHaskellDepends = [
    base containers hspec hspec-jenkins lens mtl silently streaming
    temporary text unliftio
  ];
  homepage = "https://github.com/tweag/capabilities-via";
  license = stdenv.lib.licenses.bsd3;
}
