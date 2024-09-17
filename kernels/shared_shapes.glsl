struct Circle {
    //vec2 pos;
    float r;
    float r_square;
    vec3 color;
};

struct Physics {
    vec2 pos;
    vec2 dir;
    float speed;
    float mass;
};

struct Mold_particle {
    vec2 pos;
    float angle;
    int type;
};