{-# LANGUAGE OverloadedStrings, TupleSections #-}
{-# LANGUAGE QuasiQuotes #-}

module FacilitiesImport where

import Control.Applicative ((<$>),(<*>))
import Control.Monad (void)
import Control.Concurrent.Async (mapConcurrently)
import Control.Monad.Reader (runReaderT)
import Data.Csv (FromNamedRecord,parseNamedRecord,(.:))
import Snap.Snaplet.PostgresqlSimple
import Database.PostgreSQL.Simple.SqlQQ (sql)

import Db.Internal
import Db.Facility
import Internal

instance FromNamedRecord Facility where
  parseNamedRecord m = Facility
    <$> m .: "PR_NO"
    <*> m .: "PARK_NAME"
    <*> m .: "NODE_ID"
    <*> m .: "NODE_USE"
    <*> m .: "NODES_NAME"
    <*> m .: "ITEM_ID"
    <*> m .: "ITEM_TYPE"
    <*> m .: "ITEMS_NAME"
    <*> m .: "DESCRIPTION"
    <*> m .: "EASTING"
    <*> m .: "NORTHING"
    <*> m .: "ORIG_FID"
    <*> ((,) <$> m .: "LONGITUDE" <*> m .: "LATITUDE")

importFacilities :: Postgres -> IO ()
importFacilities pg = do
  runReaderT deleteFacilities pg
  _ <- mapConcurrently (loadAndInsert pg) [1,2]
  void $ runReaderT processFeatures pg

importFacilitiesWhitelists :: Postgres -> IO ()
importFacilitiesWhitelists db = do
  runReaderT (void (execute_ "TRUNCATE node_use_whitelist")) db
  runReaderT (void (execute_ "TRUNCATE item_type_whitelist")) db
  readFile "data/node_use_whitelist.txt" >>= mapM_ insert' . lines
  readFile "data/item_type_whitelist.txt" >>= mapM_ insert'' . lines
  where
    insert' s = runReaderT (insertNodeUseWhitelist s) db
    insert'' s = runReaderT (insertItemTypeWhitelist s) db

insertItemTypeWhitelist :: String -> Db ()
insertItemTypeWhitelist s = void $ execute
  [sql|
   INSERT INTO item_type_whitelist (item_type)
   VALUES (?)
  |]
  (Only s)

insertNodeUseWhitelist :: String -> Db ()
insertNodeUseWhitelist s = void $ execute
  [sql|
   INSERT INTO node_use_whitelist (node_use)
   VALUES (?)
  |]
  (Only s)

loadAndInsert :: Postgres -> Int -> IO ()
loadAndInsert conn i = do
  c <- loadCsv (filePath i)
  runReaderT (mapM_ insertFacility c) conn

processFeatures :: Db ()
processFeatures = void $ execute_
  [sql|
    INSERT INTO park_feature (park_number, feature_id, coords)
    SELECT
      park_number,
      'dog_off_leash_area',
      ST_Centroid(ST_Collect(coords::geometry))::geography
    FROM park_facility
    WHERE node_use = 'DOG OFF LEASH NODE'
    GROUP BY park_number;
  |]

filePath :: Int -> FilePath
filePath i = "data/dataset_park_facilties_part_" ++ show i ++ ".csv"
