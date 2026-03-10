export const PLANT_CATALOG = {
  sunflower_c_su: { name: "Sunflower", assetName: "spring-common0" },
  tulip_c_sp: { name: "Tulip", assetName: "summer-common0" },
  marigold_c_fa: { name: "Marigold", assetName: "fall-common0" },
  pansy_c_wi: { name: "Pansy", assetName: "winter-common0" },
  fern_c_sp: { name: "Spring Fern", assetName: "spring-common1" },
  cactus_c_su: { name: "Desert Bloom", assetName: "summer-common1" },
  pumpkin_c_fa: { name: "Mini Pumpkin", assetName: "fall-common1" },
  holly_c_wi: { name: "Winter Holly", assetName: "winter-common1" },
  lavender_uc_su: { name: "Lavender", assetName: "spring-uncommon" },
  daffodil_uc_sp: { name: "Daffodil", assetName: "summer-uncommon" },
  aster_uc_fa: { name: "Autumn Aster", assetName: "fall-uncommon" },
  snowdrop_uc_wi: { name: "Snowdrop", assetName: "winter-uncommon" },
  rose_r_sp: { name: "Mystic Rose", assetName: "spring-rare" },
  orchid_r_su: { name: "Sun Orchid", assetName: "summer-rare" },
  nightshade_r_fa: { name: "Shadow Bloom", assetName: "fall-rare" },
  iceflower_r_wi: { name: "Ice Flower", assetName: "winter-rare" },
  moonflower_e_fa: { name: "Moonflower", assetName: "fall-epic" },
  crystalbloom_e_wi: { name: "Crystal Bloom", assetName: "winter-epic" },
  dreamlily_e_sp: { name: "Dream Lily", assetName: "spring-epic" },
  solarflare_e_su: { name: "Solar Flare", assetName: "summer-epic" },
  starpetal_l_sp: { name: "Starpetal", assetName: "spring-legendary" },
  phoenixbloom_l_su: { name: "Phoenix Bloom", assetName: "summer-legendary" },
  ancientshade_l_fa: { name: "Ancient Shade", assetName: "fall-legendary" },
  aurorafrost_l_wi: { name: "Aurora Frost", assetName: "winter-legendary" },
  withered_1: { name: "Withered Plant", assetName: "dead-shrub" },
};

export function getPlantMeta(plantId) {
  return PLANT_CATALOG[plantId] || null;
}

export function getPlantDisplayName(plantId) {
  return getPlantMeta(plantId)?.name || plantId;
}

export function resolvePlantAssetName(plant) {
  if (plant?.assetName) return plant.assetName;
  return getPlantMeta(plant?.id)?.assetName || null;
}
