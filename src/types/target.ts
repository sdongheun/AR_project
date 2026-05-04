export type MapTargetCategory = 'building' | 'tourSpot';

export type MapTarget = {
  id: string;
  name: string;
  category: MapTargetCategory;
  categoryLabel: string;
  address: string;
  latitude: number;
  longitude: number;
  altitude: number;
};
