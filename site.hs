--------------------------------------------------------------------------------
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DeriveGeneric, DeriveAnyClass #-}
import           Data.Monoid (mappend)
import           Hakyll

import qualified GHC.IO.Encoding as E
import           Data.Yaml
import           GHC.Generics

import           Data.ByteString.UTF8 (fromString)
import           Data.List.Utils (replace)
import           Control.Monad.Except
import           Control.Arrow
import           Control.Applicative

--------------------------------------------------------------------------------

-- Optional Field, if we get nothing we got an mempty
optionField :: String -> (Item a -> Compiler (Maybe String)) -> Context a
optionField key value = Context $ \k _ i -> if k == key
                                            then value i >>= maybe empty (return . StringField)
                                            else empty


mapBody f = return . f . itemBody
listCtx = field "item" . mapBody

-- Define of publication and publication context
data Publication = Publication {
    name :: String,
    authors :: String,
    site :: Maybe String,
    file :: Maybe String,
    fileUrl :: Maybe String,
    link :: Maybe String,
    note :: Maybe String,
    artifact :: Maybe String
} deriving (Generic, FromJSON)

getFileUrl a = fmap ("/files/" ++) (file a) <|> fileUrl a
boldAuthor au = replace au ("<span class=\"main-author\">" ++ au ++ "</span>")

pubCtx = field       "name"     (mapBody name)
      <> field       "authors"  (mapBody $ boldAuthor "Jiaxin Lin" . authors)
      <> optionField "site"     (mapBody site) 
      <> optionField "file"     (mapBody getFileUrl) 
      <> optionField "link"     (mapBody link) 
      <> optionField "note"     (mapBody note) 
      <> optionField "artifact" (mapBody artifact) 

-- Define of publication and publication context
data Experience = Experience {
    location :: String,
    title :: String,
    time :: String,
    logo :: String
} deriving (Generic, FromJSON)
expCtx = field "location" (mapBody location)
      <> field "title"    (mapBody title)
      <> field "time"     (mapBody time)
      <> field "logo"     (mapBody $ ("/images/logo/" ++) . logo)

parseYaml :: FromJSON a => String -> Compiler a
parseYaml = liftEither . left (return . show) . decodeEither' . fromString

wrapItemList :: [a] -> Compiler [Item a]
wrapItemList = sequence . map makeItem

-- main generator
main :: IO ()
main = do
    E.setLocaleEncoding E.utf8
    hakyll $ do
        -- static resources
        match "images/*" $ do
            route   idRoute
            compile copyFileCompiler
        match "images/logo/*" $ do
            route   idRoute
            compile copyFileCompiler

        match "css/*" $ do
            route   idRoute
            compile compressCssCompiler

        match "files/*" $ do
            route   idRoute
            compile copyFileCompiler

        -- main page
        match "index.html" $ do
            route idRoute
            compile $ do
                -- pages
                about        <- loadBody "pages/about.md"

                -- data
                publications <- parseYaml =<< loadBody "data/publications.yaml"
                experience   <- parseYaml =<< loadBody "data/experience.yaml"
                service      <- parseYaml =<< loadBody "data/service.yaml"
                artworks     <- parseYaml =<< loadBody "data/artworks.yaml" :: Compiler [Integer]

                -- news
                news         <- return . take 5 =<< recentFirst =<< loadAll "news/*"

                let indexCtx = listField  "publications" pubCtx         (wrapItemList publications)
                            <> listField  "news"         postCtx        (return news)
                            <> listField  "experience"   (listCtx id)   (wrapItemList experience)
                            <> listField  "service"      (listCtx id)   (wrapItemList service)
                            <> listField  "artworks"     (listCtx show) (wrapItemList artworks)
                            <> constField "about"        about
                            <> defaultContext

                getResourceBody
                    >>= applyAsTemplate indexCtx
                    >>= loadAndApplyTemplate "templates/default.html" indexCtx
                    >>= relativizeUrls

        -- resource files
        match "templates/*" $ compile templateBodyCompiler

        match "news/*"  $ compile $ pandocCompiler >>= relativizeUrls 
        match "pages/*" $ compile $ pandocCompiler >>= relativizeUrls 

        match "data/*" $ compile getResourceString


--------------------------------------------------------------------------------
postCtx :: Context String
postCtx =
    dateField "date" "%B %e, %Y" `mappend`
    defaultContext
