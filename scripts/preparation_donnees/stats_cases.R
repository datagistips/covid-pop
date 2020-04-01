library(tidyverse)
library(sf)

## 1. READ & PREPARE DATA ####
## Region & deps
# Télécharger les données AdminExpress depuis l'URL
# https://geoservices.ign.fr/documentation/diffusion/telechargement-donnees-libres.html#admin-express
regs <- st_read("C:/Users/mathieu/Documents/data/ADMIN-EXPRESS-COG_2-0__SHP__FRA_L93_2019-09-24/ADMIN-EXPRESS-COG_2-0__SHP__FRA_2019-09-24/ADMIN-EXPRESS-COG/1_DONNEES_LIVRAISON_2019-09-24/ADE-COG_2-0_SHP_LAMB93_FR/REGION.shp")
deps <- st_read("C:/Users/mathieu/Documents/data/ADMIN-EXPRESS-COG_2-0__SHP__FRA_L93_2019-09-24/ADMIN-EXPRESS-COG_2-0__SHP__FRA_2019-09-24/ADMIN-EXPRESS-COG/1_DONNEES_LIVRAISON_2019-09-24/ADE-COG_2-0_SHP_LAMB93_FR/DEPARTEMENT.shp")

## Covid France
download.file("https://www.data.gouv.fr/fr/datasets/r/63352e38-d353-4b54-bfd1-f1b3ee1cabd7", destfile="data/stats_france.csv")
stats_fr <- read.table("data/stats_france.csv", sep=";", header = TRUE)

## Covid World
download.file("https://raw.githubusercontent.com/CSSEGISandData/COVID-19/master/csse_covid_19_data/csse_covid_19_time_series/time_series_covid19_confirmed_global.csv", "data/stats_world.csv")
stats_world <- read_csv("data/stats_world.csv")

## Country codes
download.file("https://datahub.io/core/country-list/r/data.csv", "data/country_codes.csv")
country_codes <- read_csv("data/country_codes.csv")


## 2. STATS FR ####
stats_fr <- stats_fr %>% 
            filter(dep != "") %>%
            mutate(nb  = hosp + rea + rad + dc)

## Add dep and reg
stats_fr$lib_dep   <- deps$NOM_DEP[match(stats_fr$dep, deps$INSEE_DEP)]
stats_fr$insee_reg <- deps$INSEE_REG[match(stats_fr$dep, deps$INSEE_DEP)]
stats_fr$lib_reg   <- regs$NOM_REG[match(stats_fr$insee_reg, regs$INSEE_REG)]

## Stats par département
stats_dep <-  stats_fr %>% 
              mutate(type = "departement") %>% 
              group_by(lib_dep, type, jour) %>% 
              summarise(nb = sum(nb)) %>% 
              data.frame %>% 
              select(type, lib = lib_dep, jour, nb) %>% 
              filter(!is.na(lib))

## Stats par région
stats_reg <-  stats_fr %>%
              mutate(type="region") %>% 
              group_by(lib_reg, type, jour) %>% 
              summarise(nb = sum(nb)) %>% 
              data.frame %>% 
              select(type, lib = lib_reg, jour, nb) %>% 
              filter(!is.na(lib))

## Agrégation des stats 
stats_fr <- rbind(stats_dep, stats_reg) %>% 
            arrange(type, lib, nb) %>% 
            mutate(jour = as.Date(jour))


## 3. STATS WORLD ####
stats_world_reshaped <- stats_world[, c(2, 5:ncol(stats_world))] %>% 
                         rename(country = "Country/Region") %>% 
                         gather(date, nb_cases, -country) %>% 
                         mutate(date = as.Date(date, format="%m/%d/%y")) %>% 
                         group_by(country, date) %>% ## !! Choisir aussi les provinces
                         summarise(nb = sum(nb_cases)) %>% 
                         data.frame %>% 
                         transmute(type="country", lib=country, jour=date, nb)


## 4. STATS TOTALES ####
stats_total <- rbind(stats_fr, stats_world_reshaped)
nrow(stats_total)


## 5. COUNTRY CODES ####
source_countries <- stats_total %>% 
                    filter(type=="country") %>% 
                    pull("lib") %>% unique

## Matches and corrections
m <- match(source_countries, country_codes$Name)
df <- data.frame(country = source_countries, code = country_codes$Code[m])

## Separate data
df.ok <- df[which(!is.na(df$code)), ]
df.nok <- df[which(is.na(df$code)), ]

## Corrections
print(df.nok$country)
df.nok$code <- c("BQ", "BN", NA, "CV", "CD", "CG", "CI", 
                 "CZ", NA, NA, NA, "IR", "KP", NA, "LA", 
                 "MD", NA, "NA", "MK", "RU", "SY", "TW", "TZ", 
                 "US", "VE", "VN", "PS")

## Stick data
df <- rbind(df.ok, df.nok)


## 6. FLAGS ####

## Join with country codes for flags
stats_flags <-  stats_total %>% 
                left_join(df, by=c("lib"="country")) %>% 
                mutate(Code = tolower(code)) %>% 
                mutate(flag_url = sprintf("https://cdn.rawgit.com/lipis/flag-icon-css/master/flags/4x3/%s.svg", tolower(code)))

## Update with NA Value when no flag
stats_flags$flag_url[which(is.na(stats_flags$code))] <- NA

print(stats_flags %>% drop_na(flag_url) %>% pull(flag_url) %>% unique)


## 7. SAVE ####
write_csv(stats_flags, "data/stats.csv")