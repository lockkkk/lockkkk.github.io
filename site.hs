--------------------------------------------------------------------------------
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DuplicateRecordFields, TypeApplications #-}
{-# LANGUAGE DeriveGeneric, DeriveAnyClass #-}
import           Data.Monoid (mappend)
import           Hakyll
import           Text.Pandoc.Options (def, WriterOptions(..), TopLevelDivision(..))

import qualified GHC.IO.Encoding as E
import           Data.Yaml
import           GHC.Generics

import           Data.ByteString.UTF8 (fromString)
import           Data.List.Utils (replace)
import           Control.Monad.Except
import           Control.Arrow
import           Control.Applicative

--------------------------------------------------------------------------------
-- Configs
myName = "Jiaxin Lin"

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
    artifact :: Maybe String,
    slides :: Maybe String
} deriving (Generic, FromJSON)

getFileUrl a = fmap ("/files/" ++) (file a) <|> fileUrl a
boldAuthor au = replace au ("<span class=\"main-author\">" ++ au ++ "</span>")

pubCtx = field       "name"     (mapBody name)
      <> field       "authors"  (mapBody $ boldAuthor myName. authors)
      <> optionField "site"     (mapBody site) 
      <> optionField "file"     (mapBody getFileUrl) 
      <> optionField "link"     (mapBody (link :: Publication -> Maybe String)) 
      <> optionField "note"     (mapBody note) 
      <> optionField "artifact" (mapBody artifact) 
      <> optionField "slides"   (mapBody slides) 

-- Define of publication and publication context
data Experience = Experience {
    location :: String,
    title :: String,
    time :: String,
    logo :: String
} deriving (Generic, FromJSON)

expCtx = field "location" (mapBody (location :: Experience -> String))
      <> field "title"    (mapBody title)
      <> field "time"     (mapBody (time :: Experience -> String))
      <> field "logo"     (mapBody $ ("/images/logo/" ++) . logo)

-- Defined the awards and context
data TimedEntry = TimedEntry {
    time :: String,
    text :: String,
    location :: Maybe String,
    link :: Maybe String
} deriving (Generic, FromJSON)

timedCtx = field "time"           (mapBody (time :: TimedEntry -> String))
        <> field "text"           (mapBody text)
        <> optionField "location" (mapBody (location :: TimedEntry -> Maybe String))
        <> optionField "link"     (mapBody (link :: TimedEntry -> Maybe String))

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
                awards       <- parseYaml =<< loadBody "data/awards.yaml"
                services     <- parseYaml =<< loadBody "data/services.yaml"
                artworks     <- parseYaml =<< loadBody "data/artworks.yaml" :: Compiler [Integer]

                -- news
                news         <- return . take 5 =<< recentFirst =<< loadAll "news/*"

                -- dirs
                dirs         <- loadBody "pages/direction.md"

                let indexCtx = listField  "publications" pubCtx         (wrapItemList publications)
                            <> listField  "news"         postCtx        (return news)
                            <> listField  "experience"   expCtx         (wrapItemList experience)
                            <> listField  "awards"       timedCtx       (wrapItemList awards)
                            <> listField  "services"     timedCtx       (wrapItemList services)
                            <> listField  "artworks"     (listCtx show) (wrapItemList artworks)
                            <> constField "dirs"         dirs     
                            <> constField "about"        about
                            <> defaultContext

                getResourceBody
                    >>= applyAsTemplate indexCtx
                    >>= loadAndApplyTemplate "templates/default.html" indexCtx
                    >>= relativizeUrls

        -- resource files
        match "templates/*" $ compile templateBodyCompiler

        match "news/*"  $ compile $ pandocCompiler >>= relativizeUrls <$> (fmap inlineParagraph)
        match "pages/*" $ compile $ pandocCompiler >>= relativizeUrls

        match "data/*" $ compile getResourceString


--------------------------------------------------------------------------------
inlineParagraph :: String -> String
inlineParagraph = replace "<p>" "<span>"
                . replace "</p>" "</span>"
                . replace "<a " "<a target=\"_blank\" "

postCtx :: Context String
postCtx =
    dateField "date" "%b %Y" `mappend`
    defaultContext