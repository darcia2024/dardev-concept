export interface PackageFeature {
  text: string;
  isNew?: boolean;
  highlight?: boolean;
  explanation?: string; // Layman friendly explanation
}

export interface PackageData {
  id: 'starter' | 'standard' | 'pro';
  name: string;
  tagline: string;
  badge?: string;
  price: number;
  formattedPrice: string;
  bestFor: string;
  laymanPitch: string;
  roiPitch: string;
  features: string[];
  bugFixingDays: number;
  isRecommended?: boolean;
  colorScheme: {
    accent: string;
    border: string;
    bgGlow: string;
    badgeBg: string;
    badgeText: string;
  };
}

export interface AddOnItem {
  id: string;
  name: string;
  price: number;
  formattedPrice: string;
  description: string;
  benefit: string;
  isThirdPartyNote?: boolean;
}

export interface FeatureComparisonRow {
  category: string;
  name: string;
  laymanDescription: string;
  starter: boolean | string;
  standard: boolean | string;
  pro: boolean | string;
}

export interface FaqItem {
  question: string;
  answer: string;
  category: 'biaya' | 'fitur' | 'teknis' | 'pengerjaan' | 'layanan';
}

export interface SlideItem {
  id: string;
  title: string;
  subtitle: string;
  category: string;
}
