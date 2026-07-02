shader_type spatial;
// Sprint 16 : recolore le sprite du nain par region (cheveux, barbe,
// vetements, armure) a partir d'un masque de couleurs reperes peint sur
// nain_mask.png. Chaque region est reconstruite a partir de sa luminance
// d'origine (donc l'ombrage/le relief du dessin est conserve) multipliee
// par la couleur choisie pour cette region.
//
// Important : les shaders spatiaux Godot n'ont pas de render_mode "billboard"
// (verifie aupres de la doc officielle) ; le billboard (faire toujours face
// a la camera) est donc gere a la main, cote script, dans Dwarf.gd plutot
// que dans ce shader.
render_mode cull_disabled, diffuse_lambert, specular_disabled;

uniform sampler2D albedo_tex : source_color;
uniform sampler2D mask_tex : filter_nearest;
uniform sampler2D normal_tex : hint_normal;

uniform vec4 hair_color : source_color = vec4(0.59, 0.45, 0.33, 1.0);
uniform vec4 beard_color : source_color = vec4(0.80, 0.71, 0.53, 1.0);
uniform vec4 clothing_color : source_color = vec4(0.68, 0.51, 0.41, 1.0);
uniform vec4 armor_color : source_color = vec4(0.55, 0.55, 0.58, 1.0);

void fragment() {
	vec4 tex_color = texture(albedo_tex, UV);
	vec3 mask = texture(mask_tex, UV).rgb;

	// Luminance du pixel d'origine : sert de "relief"/ombrage a conserver
	float luminance = dot(tex_color.rgb, vec3(0.299, 0.587, 0.114));
	vec3 recolored = tex_color.rgb;

	// Les couleurs reperes du masque sont pures (0 ou 1 par canal) :
	// un simple seuil a 0.5 par canal suffit a identifier la region.
	bool is_hair     = mask.r > 0.5 && mask.g < 0.5 && mask.b < 0.5;
	bool is_beard     = mask.g > 0.5 && mask.r < 0.5 && mask.b < 0.5;
	bool is_clothing = mask.b > 0.5 && mask.r < 0.5 && mask.g < 0.5;
	bool is_armor     = mask.r > 0.5 && mask.g > 0.5 && mask.b < 0.5;

	// Pas de "boost" de luminance : recolored = teinte * luminance, pour que
	// la teinte cible reste fidele meme sur les zones tres claires (barbe
	// blanche/grise par exemple, dont beaucoup de pixels sont deja proches
	// du blanc). Teste visuellement : un facteur > 1 delave les teintes
	// sombres vers le blanc sur ce genre de zones.
	if (is_hair) {
		recolored = clamp(hair_color.rgb * luminance, 0.0, 1.0);
	} else if (is_beard) {
		recolored = clamp(beard_color.rgb * luminance, 0.0, 1.0);
	} else if (is_clothing) {
		recolored = clamp(clothing_color.rgb * luminance, 0.0, 1.0);
	} else if (is_armor) {
		recolored = clamp(armor_color.rgb * luminance, 0.0, 1.0);
	}

	ALBEDO = recolored;
	ALPHA = tex_color.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	NORMAL_MAP = texture(normal_tex, UV).rgb;
}
