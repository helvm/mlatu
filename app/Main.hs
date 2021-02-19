module Main where

import Arguments (Arguments, parseArguments)
import Arguments qualified
-- import Data.Time.Clock (diffUTCTime, getCurrentTime, nominalDiffTimeToSeconds)
import Interact qualified
import Mlatu (compile, compilePrelude, runMlatu)
import Mlatu.Interpret (interpret)
import Mlatu.Name (GeneralName (..), Qualified (..))
import Mlatu.Vocabulary qualified as Vocabulary
import Relude
import Report (reportAll)
import System.Directory (makeAbsolute)
import System.IO (hPutStrLn, hSetEncoding, utf8)

main :: IO ()
main = do
  hSetEncoding stdout utf8
  arguments <- parseArguments
  case Arguments.inputPaths arguments of
    [] -> case Arguments.compileMode arguments of
      Arguments.CheckMode -> do
        hPutStrLn stderr "Cannot run interactively in check mode."
        exitFailure
      Arguments.InterpretMode -> Interact.run (Arguments.prelude arguments)
    (_ : _) -> runBatch arguments

runBatch :: Arguments -> IO ()
runBatch arguments = do
  paths <- forM (Arguments.inputPaths arguments) makeAbsolute
  commonResult <- runMlatu $ compilePrelude (Arguments.prelude arguments) mainPermissions Nothing
  case commonResult of 
    Left reports -> do 
      reportAll reports
      exitFailure
    Right commonDictionary -> do 
        result <- runMlatu $ compile mainPermissions Nothing paths (Just commonDictionary)
        case result of
          Left reports -> do
            reportAll reports
            exitFailure
          Right program ->
            case Arguments.compileMode arguments of
              Arguments.CheckMode -> pass
              Arguments.InterpretMode ->
                void $ interpret program Nothing [] stdin stdout stderr []
  where
    mainPermissions =
      [ QualifiedName $ Qualified Vocabulary.global "IO",
        QualifiedName $ Qualified Vocabulary.global "Fail"
      ]