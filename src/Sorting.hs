module Sorting where

import Syntax
import Data.List(partition)
import Data.Generics.Uniplate.Data(transformBi, para)


-- Sorting of declarations in let bindings and modules
sortDeclsMod x = (transformBi f . transformBi k) x
  where
    f (LetExpression decls e) =
        LetExpression (sortDecls fromId decls) e
    f e = e

    k (ModuleDeclaration modName decls) =
        ModuleDeclaration modName
            (sortDecls (qualifyId modName) decls)

sortDecls qual decls =
    let
        -- Top-level definitions are qualified with the module name
        getDefs = fmap qual . getDefsD

        -- Only look at the dependency on local variables
        localDefs = foldMap getDefs decls
        getLocalDeps = including localDefs . getDepsD

        -- Remove recursive dependency on itself
        getDeps decl = excluding (getDefs decl) (getLocalDeps decl)
    in resolve getDefs getDeps [] decls

resolve getDefs getDeps done rest =
    case partition (null . excluding done . getDeps) rest of
        ([], []) -> []
        ([], ys) ->
            error ("Cyclic dependency in " ++ pretty (fmap getDeps ys))
        (xs, ys) ->
            -- in the first run, xs contains all type signatures
            -- they have no value dependencies but define an id
            -- here these ids get marked as done which allows cycles
            let doneDefs = concatMap getDefs xs
            in xs ++ resolve getDefs getDeps (doneDefs ++ done) ys

sortModules = resolve (return . getName) gatherImports []

gatherImports modDecl = fmap fst (gatherSpecs modDecl)

gatherSpecs modDecl = 
    [(name, spec) | ImportDeclaration name spec _ <- getDecls modDecl]


--Gather variables used in an expression
--The second argument of f contains
--the dependencies of the child expressions
getDepsE e =
    let
        f (Variable v) _ = [v]
        f (ConstructorExpression c) _ = [c]
        f (CaseExpression _ alts) (deps:cs) =
            concat (deps : zipWith (\(p, _) c ->
                excluding (fmap fromId (getDefsP p)) c) alts cs)
        f (LambdaExpression ps _) cs =
            excluding (foldMap (fmap fromId . getDefsP) ps)
                (concat cs)
        f (LetExpression decls _) cs =
            excluding (foldMap (fmap fromId . getDefsD) decls)
                (concat cs)
        f _ cs = concat cs
    in para f e

getDepsD (ExpressionDeclaration _ e) = getDepsE e
getDepsD _ = []
