{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE ExistentialQuantification #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE RecordWildCards #-}
module Main where

--------------------------------------------------------------------------------
import Control.Applicative
import Control.Concurrent (threadDelay)
import Control.Error ((??))
import Control.Exception (Exception, toException)
import Control.Monad (forever, join, void, when)
import Data.Aeson ((.=))
import Data.Ix (inRange)
import Data.List (intercalate)
import Data.Maybe (fromMaybe, listToMaybe)
import Data.Monoid (mempty)
import Data.Typeable (Typeable)
import Database.PostgreSQL.Simple.SqlQQ (sql)


--------------------------------------------------------------------------------
import qualified Aws as AWS
import qualified Aws.Core as AWS
import qualified Aws.S3 as S3
import qualified Blaze.ByteString.Builder.Char8 as Builder
import qualified Control.Concurrent.Async as Async
import qualified Control.Monad.Trans.Either as EitherT
import qualified Control.Monad.Trans.Resource as ResourceT
import qualified Data.Aeson as Aeson
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as Char8
import qualified Data.ByteString.Lazy as LBS
import qualified Data.Configurator as Configurator
import qualified Data.Map.Lazy as Map
import qualified Data.Text as Text
import qualified Data.Text.Encoding as Text
import qualified Data.UUID as UUID
import qualified Data.Vector as Vector
import qualified Database.PostgreSQL.Simple as Pg
import qualified Database.PostgreSQL.Simple.FromField as Pg
import qualified Database.PostgreSQL.Simple.FromRow as Pg
import qualified Database.PostgreSQL.Simple.ToField as Pg
import qualified Network.AMQP as AMQP
import qualified Network.AMQP.Types as AMQP
import qualified Network.HTTP.Conduit as HTTP
import qualified Network.HTTP.Types as HTTP
import qualified Text.XML.Light as XML


--------------------------------------------------------------------------------
-- | An 'EventHandler' listens for messages with a specific routing key (given
-- by 'eventRoutingKey'). When a message with this routing key is seen, the
-- 'eventParser' is used to try and parse this message into a coherent payload.
-- If this is possible, the 'eventAction' is invoked with the parsed payload.
data EventHandler = forall payload. EventHandler
  { eventRoutingKey :: Text.Text
  , eventParser :: String -> Maybe payload
  , eventAction :: HandlerEnv -> payload -> IO ()
  }


--------------------------------------------------------------------------------
-- | All 'EventHandler's 'eventAction's run within this environment.
data HandlerEnv = HandlerEnv
  { handlerPg :: Pg.Connection
  , handlerAws :: AWS.Configuration
  , handlerS3 :: S3.S3Configuration AWS.NormalQuery
  }


--------------------------------------------------------------------------------
data CAAException = MessageBodyParseFailure
  deriving (Show, Typeable)

instance Exception CAAException


--------------------------------------------------------------------------------
-- | The \"index\" 'EventHandler' is used to re-index a release. This involves
-- creating a new @index.json@ file and refreshing @mb_metadata.xml@.
index :: EventHandler
index = EventHandler
  { eventRoutingKey = "index"

  , eventParser = UUID.fromString

  , eventAction = \HandlerEnv{..} uuid -> do
      mrelease <- findRelease handlerPg uuid
      case mrelease of
        Nothing -> return ()
        Just (releaseGid, releaseId) -> do
          images <- listImages handlerPg releaseId
          let aws = handlerAws; s3 = handlerS3
          uploadIndexListing aws s3 (IndexListing releaseGid images)
          refreshMetadataXml aws s3 releaseGid
  }

 where

  findRelease pg uuid = listToMaybe <$> Pg.query pg q (uuid, uuid)
   where
    q = [sql|
          SELECT release.gid, release.id
          FROM musicbrainz.release
          JOIN musicbrainz.release_name name ON name.id = release.name
          JOIN musicbrainz.artist_credit
            ON artist_credit.id = release.artist_credit
          JOIN musicbrainz.artist_name ac_name
            ON ac_name.id = artist_credit.name
          WHERE release.id IN (
            SELECT new_id FROM musicbrainz.release_gid_redirect
            WHERE gid = ?
            UNION
            SELECT id FROM musicbrainz.release
            WHERE gid = ?
          )
        |]

  listImages :: Pg.Connection -> Int -> IO [ReleaseImage]
  listImages pg releaseId = Pg.query pg q (Pg.Only releaseId)
   where
    q = [sql|
          SELECT caa.types, caa.is_front, caa.is_back, caa.comment, caa.id,
            release.gid, caa.approved, caa.edit
          FROM cover_art_archive.index_listing caa
          JOIN release ON release.id = caa.release
          WHERE caa.release = ?
          ORDER BY ordering
        |]

  uploadIndexListing awsCfg s3Cfg indexListing = HTTP.withManager $ \mgr ->
    runPut awsCfg s3Cfg mgr $
      (put (indexRelease indexListing) "index.json" (Aeson.encode indexListing))
        { S3.poMetadata = [ contentType "application/json; charset=utf-8" ] }

  refreshMetadataXml awsCfg s3Cfg release = void $ do
    HTTP.withManager $ \mgr -> do
      metadata <- do
        req <- HTTP.parseUrl $
          "http://0.0.0.0:6000/ws/2/release/" ++ UUID.toString release ++ "?inc=artists"
        HTTP.responseBody <$> HTTP.httpLbs req mgr

      runPut awsCfg s3Cfg mgr $
        (put release (bucket release ++ "_mb_metadata.xml") metadata)
        { S3.poMetadata = [ contentType "application/xml; charset=utf-8" ] }

  contentType t = ("Content-Type", t)


--------------------------------------------------------------------------------
-- | An 'IndexListing' for a release pairs a MBID with a list of 'ReleaseImage's
data IndexListing = IndexListing
  { indexRelease :: UUID.UUID
  , indexImages :: [ReleaseImage]
  }


-- | A 'ReleaseImage' is a single image the index listing for a release.
data ReleaseImage = ReleaseImage
  { imageTypes :: Vector.Vector Text.Text
  , imageIsFront :: Bool
  , imageIsBack :: Bool
  , imageComment :: Text.Text
  , imageId :: Int
  , imageRelease :: UUID.UUID
  , imageApproved :: Bool
  , imageEdit :: Int
  }


instance Aeson.ToJSON IndexListing where
  toJSON IndexListing{..} = Aeson.object
    [ "images" .= indexImages
    , "release" .= ("http://musicbrainz.org/release/" ++ UUID.toString indexRelease)
    ]

instance Aeson.ToJSON ReleaseImage where
  toJSON ReleaseImage{..} = Aeson.object
    [ "types" .= imageTypes
    , "front" .= imageIsFront
    , "back" .= imageIsBack
    , "comment" .= imageComment
    , "image" .= imageUrl Nothing
    , "thumbnails" .= Aeson.object
        [ "small" .= imageUrl (Just 250)
        , "large" .= imageUrl (Just 500)
        ]
    , "approved" .= imageApproved
    , "edit" .= imageEdit
    , "id" .= imageId
    ]

   where

    caaUrl suffix =
      "http://coverartarchive.org/release/" ++ UUID.toString imageRelease ++
        "/" ++ show imageId ++ suffix ++ ".jpg"

    imageUrl :: Maybe Int -> String
    imageUrl (Just thumbnailSize) = caaUrl ("-" ++ show thumbnailSize)
    imageUrl Nothing = caaUrl ""


instance Pg.FromRow ReleaseImage where
  fromRow = ReleaseImage <$> Pg.field <*> Pg.field <*> Pg.field <*> Pg.field
                         <*> Pg.field <*> Pg.field <*> Pg.field <*> Pg.field


instance Pg.ToField UUID.UUID where
  toField = Pg.Plain . Pg.inQuotes . Builder.fromString . UUID.toString


instance Pg.FromField UUID.UUID where
  fromField f Nothing = Pg.returnError Pg.UnexpectedNull f "UUID cannot be null"
  fromField f (Just v) = do
    t <- Pg.typename f
    if t /= "uuid" then incompatible else tryParse
    where
      incompatible = Pg.returnError Pg.Incompatible f "UUIDs must be PG type 'uuid'"
      tryParse = case UUID.fromString (Char8.unpack v) of
        Just uuid -> return uuid
        Nothing -> Pg.returnError Pg.ConversionFailed f "Not a valid UUID"


--------------------------------------------------------------------------------
data MovePayload = MovePayload
  { moveId :: Int
  , moveOldMbid :: UUID.UUID
  , moveNewMbid :: UUID.UUID
  }

-- | The \"move\" 'EventHandler' copy's an item from one bucket into another
-- bucket, and deletes the original item.
move :: EventHandler
move = EventHandler
  { eventRoutingKey = "move"

  , eventParser = \s -> do
      (key : old : new : _) <- pure (lines s)
      MovePayload <$> read key <*> UUID.fromString old <*> UUID.fromString new

  , eventAction = \HandlerEnv{..} MovePayload{..} -> void $ do
      copy handlerAws handlerS3 moveId moveOldMbid moveNewMbid
      deleteOriginal handlerAws handlerS3 moveOldMbid moveId
  }

 where

  copy awsCfg s3Cfg key oldBucket newBucket = HTTP.withManager $ \mgr ->
    runPut awsCfg s3Cfg mgr $
      (put newBucket (imageKey newBucket key) LBS.empty)
      { S3.poMetadata =
          [ ("x-amz-copy-source"
            , Text.pack $ "/" ++ bucket oldBucket ++ "/" ++ imageKey oldBucket key)
          ]
      }

  deleteOriginal awsCfg s3Cfg b key = HTTP.withManager $ \mgr -> do
    -- Run with AWS.aws because we don't care about errors, and instead assume
    -- the deletion succeeded.
    AWS.aws awsCfg s3Cfg mgr $
      S3.DeleteObject
        { doObjectName = Text.pack (imageKey b key)
        , doBucket = Text.pack (bucket b)
        }

  imageKey b key = bucket b ++ "-" ++ show key ++ ".jpg"


--------------------------------------------------------------------------------
data DeletePayload = DeletePayload
  { deleteKey :: String
  , deleteMbid :: UUID.UUID
  }

-- | The \"delete\" 'EventHandler' deletes artwork from a releases bucket.
delete :: EventHandler
delete = EventHandler
  { eventRoutingKey = "delete"

  , eventParser = \s -> do
      (originalKey : mbid : _) <- pure (lines s)
      parsedMbid <- UUID.fromString mbid
      return $
        DeletePayload
          { deleteKey =
              if originalKey == "index.json"
                then originalKey
                else intercalate "-" [ "mbid"
                                     , UUID.toString parsedMbid
                                     , originalKey ++ ".jpg"
                                     ]
          , deleteMbid = parsedMbid
          }

  , eventAction = \HandlerEnv{..} DeletePayload{..} -> do
      response <- deleteObject handlerAws handlerS3 deleteMbid deleteKey

      when (not . success $ response) $
        case errorMessage response of
          Just "FATAL ERROR: cannot be retrieved" -> return ()
          _ -> error "Something went wrong"
  }

 where

  deleteObject aws s3 b key = HTTP.withManager $ \mgr -> do
    -- S3.S3Configuration carries a phantom type that we need to vary, which
    -- unfortunately means cloning the configuration.
    let s3' = case s3 of
                S3.S3Configuration a b c d e f -> S3.S3Configuration a b c d e f

    req <- HTTP.parseUrl . Char8.unpack =<<
      AWS.awsUri aws s3'
        S3.DeleteObject { S3.doObjectName = Text.pack key
                        , S3.doBucket = Text.pack (bucket b)
                        }
    HTTP.httpLbs req mgr

  errorMessage response =
    XML.parseXMLDoc (HTTP.responseBody response) >>=
    XML.findChild (XML.unqual "Error") >>=
    XML.findChild (XML.unqual "Resource") >>=
    pure . XML.strContent

  success res = inRange (200, 399) (HTTP.statusCode . HTTP.responseStatus $ res)


--------------------------------------------------------------------------------
main :: IO ()
main = do
  config <- Configurator.load [ Configurator.Required "caa-indexer.cfg" ]

  pg <- pgConnectionFromConfig config
  rabbitConn <- rabbitMqFromConfig config
  awsCfg <- awsConfig config
  s3Cfg <- s3Config config

  establishRabbitMqConfiguration rabbitConn
  bindHandlers rabbitConn (HandlerEnv pg awsCfg s3Cfg)

  forever (threadDelay 1000000)

 where

  pgConnectionFromConfig config =
    let opt key def =
          Configurator.lookupDefault (def Pg.defaultConnectInfo) config key
        parseConfig = Pg.ConnectInfo
          <$> opt "db.host" Pg.connectHost
          <*> opt "db.port" Pg.connectPort
          <*> opt "db.user" Pg.connectUser
          <*> opt "db.password" Pg.connectPassword
          <*> opt "db.database" Pg.connectDatabase

    in parseConfig >>= Pg.connect

  rabbitMqFromConfig config = join $ AMQP.openConnection
    <$> Configurator.require config "rabbitmq.host"
    <*> Configurator.require config "rabbitmq.vhost"
    <*> Configurator.require config "rabbitmq.user"
    <*> Configurator.require config "rabbitmq.password"

  awsConfig config = do
    credentials <- AWS.Credentials
      <$> Configurator.require config "s3.public"
      <*> Configurator.require config "s3.private"

    return AWS.Configuration
      { AWS.timeInfo = AWS.Timestamp
      , AWS.credentials = credentials
      , AWS.logger = \_ _ -> return ()
      }

  s3Config config = do
    s3Host <- Configurator.lookupDefault "s3.us.archive.org" config "s3.host"
    s3Port <- Configurator.lookupDefault 80 config "s3.port"

    return (S3.s3 AWS.HTTP s3Host False)
      { S3.s3RequestStyle = S3.BucketStyle
      , S3.s3Port = s3Port
      }


--------------------------------------------------------------------------------
-- | Start all 'EventHandler's
bindHandlers :: AMQP.Connection -> HandlerEnv -> IO ()
bindHandlers rabbitMq env = mapM_ establishHandler [ delete, index, move ]

 where

  establishHandler eventHandler@EventHandler{..} = do
    let handlerQueue = Text.append "cover-art-archive." eventRoutingKey

    handlerChan <- AMQP.openChannel rabbitMq
    void $ AMQP.declareQueue handlerChan
             AMQP.newQueue { AMQP.queueName = handlerQueue }
    AMQP.bindQueue handlerChan handlerQueue caaExchange eventRoutingKey
    AMQP.consumeMsgs handlerChan handlerQueue AMQP.Ack
      (uncurry $ handlerFor eventHandler handlerChan)

  handlerFor EventHandler{..} handlerChan msg envelope = do
    let messageBody = Text.unpack . Text.decodeUtf8 . BS.concat . LBS.toChunks $
                        AMQP.msgBody msg

    EitherT.eitherT
      (retry msg handlerChan eventRoutingKey)
      (const $ return ()) $
      (do payload <-
           eventParser messageBody ?? (toException MessageBodyParseFailure)

          EitherT.EitherT $
            Async.withAsync (eventAction env payload) Async.waitCatch)

    AMQP.ackEnv envelope

  ------------------------------------------------------------------------------

  retry msg handlerChan key e =
    let retriesRemaining = retries msg - 1
    in AMQP.publishMsg handlerChan (failureExchange retriesRemaining)
         key
         (msg { AMQP.msgHeaders = Just $
                     logException e .  setRetries retriesRemaining $
                     fromMaybe (AMQP.FieldTable mempty) $
                         AMQP.msgHeaders msg
                 })

  retries msg =
    case AMQP.msgHeaders msg >>= lookupHeader retryHeader of
      Just (AMQP.FVInt32 i) -> i
      _ -> defaultRetries

  failureExchange retriesRemaining
    | retriesRemaining > 0 = retryExchange
    | otherwise            = failedExchange

  logException e (AMQP.FieldTable m) = AMQP.FieldTable $ Map.insert
    "mb-exceptions"
    (AMQP.FVFieldArray $
       (AMQP.FVString (Text.pack . show $ e) : lookupArray "mb-exceptions" m))
    m

  setRetries n (AMQP.FieldTable m) = AMQP.FieldTable $
    Map.insert retryHeader (AMQP.FVInt32 n) m

  retryHeader = "mb-retries"

  defaultRetries = 4

  lookupHeader k (AMQP.FieldTable m) = Map.lookup k m

  lookupArray k m = case Map.lookup k m of
    Just (AMQP.FVFieldArray a) -> a
    _ -> []


--------------------------------------------------------------------------------
establishRabbitMqConfiguration :: AMQP.Connection -> IO ()
establishRabbitMqConfiguration rabbitConn = do
  rabbitMq <- AMQP.openChannel rabbitConn
  mapM_ (AMQP.declareExchange rabbitMq)
    [ AMQP.newExchange { AMQP.exchangeName = caaExchange
                       , AMQP.exchangeType = "direct"
                       }
    , AMQP.newExchange { AMQP.exchangeName = failedExchange
                       , AMQP.exchangeType = "fanout"
                       }
    , AMQP.newExchange { AMQP.exchangeName = retryExchange
                       , AMQP.exchangeType = "fanout"
                       }
    ]

  mapM_ (AMQP.declareQueue rabbitMq)
    [ AMQP.newQueue
        { AMQP.queueName = retryQueue
        , AMQP.queueHeaders = AMQP.FieldTable . Map.fromList $
            [ ("x-message-ttl", AMQP.FVInt32 $ 4 * 60 * 60 * 1000) -- 4 hours
            , ("x-dead-letter-exchange", AMQP.FVString "cover-art-archive")
            ]
        }
    , AMQP.newQueue { AMQP.queueName = failedQueue }
    ]

  mapM_ (\(queue, exchange) -> AMQP.bindQueue rabbitMq queue exchange "")
    [ (retryQueue, retryExchange)
    , (failedQueue, failedExchange)
    ]

 where

  retryQueue = "cover-art-archive.retry"

  failedQueue = "cover-art-archive.failed"


--------------------------------------------------------------------------------
caaExchange, retryExchange, failedExchange :: Text.Text
caaExchange = "cover-art-archive"
retryExchange = "cover-art-archive.retry"
failedExchange = "cover-art-archive.failed"


--------------------------------------------------------------------------------
-- | Convert a release MBID into a bucket name.
bucket :: UUID.UUID -> String
bucket release = "mbid" ++ UUID.toString release


--------------------------------------------------------------------------------
-- | Form a PUT request with a specific body for a specific release MBID and
-- object key.
put :: UUID.UUID -> String -> LBS.ByteString -> S3.PutObject
put release key body =
  S3.putObject (Text.pack $ bucket release) (Text.pack key)
    (HTTP.RequestBodyLBS body)


--------------------------------------------------------------------------------
runPut
    :: AWS.Configuration -> S3.S3Configuration AWS.NormalQuery -> HTTP.Manager
    -> S3.PutObject -> ResourceT.ResourceT IO ()
runPut awsCfg s3Cfg mgr request =
  void $ AWS.pureAws awsCfg s3Cfg mgr $ request
    { S3.poMetadata = [ ("x-archive-meta-collection", "coverartarchive")
                      , ("x-archive-auto-make-bucket", "1")
                      ] ++ S3.poMetadata request
    }
